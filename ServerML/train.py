from __future__ import division

from keras.callbacks import LearningRateScheduler, ModelCheckpoint, Callback
from keras.optimizers import SGD
from keras import backend as K
from clr_callback import CyclicLR
from weighted_learning import WeightedLR
from numpy.random import RandomState
import time
import model
import images
import numpy as np
import os
import gc
import comm
import random
import os
import glob
import re
import gc
import scipy.misc

import coremltools   
import h5py
import struct
from text_histogram import histogram


flippyThreshold = 0.05

coreMLPublisher = comm.publisher(comm.endpoint_pub_CoreMLUpdates)


def TrainingRunPath(runNumber=None):
    if runNumber == None:
        runNumber = trainingRunNumber
    return "./run" + str(runNumber) + "/"

def PermanentMemoryPath():
    return "./run0/pmemory/"

def TrainingMemoryPath(runNumber=None):
    if runNumber == None:
        runNumber = trainingRunNumber
    return "./run" + str(runNumber) + "/memory/"

def WasteMemoryPath(runNumber=None):
    if runNumber == None:
        runNumber = trainingRunNumber
    return "./run" + str(runNumber) + "/waste/"

def ModelWeightsPath(runNumber=None):
    if runNumber == None:
        runNumber = trainingRunNumber
    return "./run" + str(runNumber) + "/model.h5"

def CoreMLPath(runNumber=None):
    if runNumber == None:
        runNumber = trainingRunNumber
    return "./run" + str(runNumber) + "/model.mlmodel"

def ModelMessagePath(runNumber=None):
    if runNumber == None:
        runNumber = trainingRunNumber
    return "./run" + str(runNumber) + "/model.msg"


def read_file(path):
    with open(path, 'rb') as f:
        return f.read()


def GenerateSampleOrdering(total_labels, total_weights):
    # start with the normalized weights; this will allow our wasted and normal samples to gradiate nicely
    sampling_order = GenerateSampleWeights(total_labels, total_weights)
    
    # find all of the permanent memories and prioritize those!
    # If the array will be reversed, then we need to set a low priority (so that it becomes high)
    for i in range(0,len(total_labels)):
        
        
        #sampling_order[i] = 1.0 - sampling_order[i]
        #if total_weights[i] > 0 and total_labels[i][0] == 0 and total_labels[i][1] == 0:
        #    sampling_order[i] = 2.0
        
        
        # all random
        sampling_order[i] = random.random()
        
        # perm > all, rest are randomized
        #sampling_order[i] = random.random() * 0.9
        #if total_weights[i] > 0 and total_labels[i][0] == 0 and total_labels[i][1] == 0:
        #    sampling_order[i] = 1.0
        
        
        # weighted order, with perms on top
        #if total_weights[i] > 0 and total_labels[i][0] == 0 and total_labels[i][1] == 0:
        #    sampling_order[i] = 1.1
        
    return sampling_order

def GenerateSampleWeights(total_labels, total_weights, global_weight=1.0):
    
    # Arguably, we have a hierarchy of classes of samples
    # - Permanent Memoriers vs (Wasted Memories vs (Right vs Left))
    
    normalized_weights = np.zeros(len(total_weights), dtype='float32')
    max_weight = max(total_weights)
    
    numPermanent = 0
    numWasted = 0
    numLeft = 0
    numRight = 0
    
    totalLeftWeight = 0
    totalRightWeight = 0
    totalWastedWeight = 0
    
    for i in range(0,len(total_labels)):
        if total_labels[i][0] == 1:
            numLeft += 1
            totalLeftWeight += total_weights[i]
        elif total_labels[i][1] == 1:
            numRight += 1
            totalRightWeight += total_weights[i]
        else:
            if total_weights[i] < 0:
                numWasted += 1
                totalWastedWeight += total_weights[i]
            else:
                numPermanent += 1
                
    
    leftMod = numLeft / (numLeft + numRight)
    wastedMod = numWasted / (numLeft + numRight + numWasted)
    permanentMod = numPermanent / (numLeft + numRight + numWasted + numPermanent)
    
    print("permanentMod",permanentMod,"wastedMod",wastedMod,"leftMod",leftMod)
    
    left = 0
    right = 0
    wasted = 0
    permanent = 0
    
    for i in range(0,len(total_weights)):
                
        # wasted memories are balanced against "normal" left/right action memories
        if total_weights[i] < 0:
            #(total_weights[i] / totalWastedWeight * numWasted) * 
            normalized_weights[i] = (total_weights[i] / totalWastedWeight * numWasted) * (1.0 - wastedMod) * permanentMod * 1
            wasted += normalized_weights[i]
        else:
            # left memories are balanced against right memories, and are weighted by their own scores
            if total_labels[i][0] == 1:
                normalized_weights[i] = (total_weights[i] / totalLeftWeight * numLeft) * permanentMod * wastedMod * (1.0 - leftMod) * 4
                left += normalized_weights[i]
            # right memories are balanced against left memories, and are weighted by their own scores
            elif total_labels[i][1] == 1:
                normalized_weights[i] = (total_weights[i] / totalRightWeight * numRight) * permanentMod * wastedMod * leftMod * 4
                right += normalized_weights[i]
            # permanent and erroneous memories (false positive right/left memories manually corrected) count as a wasted memory
            else:
                normalized_weights[i] = 1.0 - permanentMod
                permanent += normalized_weights[i]

        normalized_weights[i] *= global_weight
    
    print("permanent",permanent,"wasted",wasted,"left",left,"right",right)
    
    return normalized_weights
                                

def ConfirmTrainingNumber():
    global trainingRunNumber
    
    trainingRunNumber = 0
    
    # figure out what run # we are on based on the existance of run# folders
    all_run_paths = glob.glob(os.path.join("./", 'run*'))
    for img_path in all_run_paths:
        m = re.search(r'\d+$', img_path)
        if m:
            n = int(m.group())
            if n > trainingRunNumber:
                trainingRunNumber = n

trainingRunNumber = 0
ConfirmTrainingNumber()


def GatherImagesFromTrainingRun(runNumber,adjustWeights,maxImagesTrain,maxImagesPerm,maxImagesWaste):
    train_labels = []
    train_weights = []
    if maxImagesTrain >= 0:
        train_imgs = images.generate_image_array(TrainingMemoryPath(runNumber), maxImagesTrain)
        images.load_images(train_imgs, train_labels, train_weights, TrainingMemoryPath(runNumber), maxImagesTrain)
    
    permanent_labels = []
    permanent_weights = []
    if maxImagesPerm >= 0:
        permanent_imgs = images.generate_image_array(PermanentMemoryPath(), maxImagesPerm)
        images.load_images(permanent_imgs, permanent_labels, permanent_weights, PermanentMemoryPath(), maxImagesPerm)
        
    waste_labels = []
    waste_weights = []
    if maxImagesWaste >= 0:
        waste_imgs = images.generate_image_array(WasteMemoryPath(runNumber), maxImagesWaste)
        images.load_images(waste_imgs, waste_labels, waste_weights, WasteMemoryPath(runNumber), maxImagesWaste)
    
    # adjust all weights by distance in the past
    train_weights = [x * adjustWeights for x in train_weights]
    permanent_weights = [x * adjustWeights for x in permanent_weights]
    waste_weights = [x * adjustWeights for x in waste_weights]    
        
    
    # combine the arrays
    total_imgs = []
    total_labels = []
    total_weights = []
    
    if len(permanent_labels) > 0:
        total_imgs = np.concatenate((total_imgs,permanent_imgs), axis=0) if len(total_imgs) > 0 else permanent_imgs
        total_labels = np.concatenate((total_labels,permanent_labels), axis=0) if len(total_labels) > 0 else permanent_labels
        total_weights = np.concatenate((total_weights,permanent_weights), axis=0) if len(total_weights) > 0 else permanent_weights
    
    if len(train_labels) > 0:
        total_imgs = np.concatenate((total_imgs,train_imgs), axis=0) if len(total_imgs) > 0 else train_imgs
        total_labels = np.concatenate((total_labels,train_labels), axis=0) if len(total_labels) > 0 else train_labels
        total_weights = np.concatenate((total_weights,train_weights), axis=0) if len(total_weights) > 0 else train_weights
    
    if len(waste_labels) > 0:
        total_imgs = np.concatenate((total_imgs,waste_imgs), axis=0) if len(total_imgs) > 0 else waste_imgs
        total_labels = np.concatenate((total_labels,waste_labels), axis=0) if len(total_labels) > 0 else waste_labels
        total_weights = np.concatenate((total_weights,waste_weights), axis=0) if len(total_weights) > 0 else waste_weights
    
    return (total_imgs,total_labels,total_weights)



def EvaluateLeftAndRightMeansForModel(label_format,cnn_model,total_imgs,total_labels,total_weights,shouldPrint=True):
    # now that we have all of the images we want, predict against them all
    predictions = cnn_model.predict(total_imgs)
    
    # we only care about the good memories and the perm memories
    left_predictions = []
    left_weights = []
    
    right_predictions = []
    right_weights = []
    
    numCorrect = 0
    numTotal = len(total_labels)
    
    for i in range(0,numTotal):
        if round(predictions[i][0]) == round(total_labels[i][0]) and round(predictions[i][1]) == round(total_labels[i][1]):
            numCorrect = numCorrect + 1
        if total_labels[i][0] == 1:
            left_predictions.append(predictions[i][0])
            left_weights.append(total_weights[i])
        elif total_labels[i][1] == 1:
            right_predictions.append(predictions[i][1])
            right_weights.append(total_weights[i])
        else:
            left_predictions.append(predictions[i][0])
            left_weights.append(total_weights[i])
            right_predictions.append(predictions[i][1])
            right_weights.append(total_weights[i])
                        
    acc = numCorrect / numTotal
        
    leftRange,leftSD,leftMean,leftMedian,leftMax = histogram(left_predictions, left_weights, buckets=20, shouldPrint=shouldPrint)
    rightRange,rightSD,rightMean,rightMedian,rightMax = histogram(right_predictions, right_weights, buckets=20, shouldPrint=shouldPrint)
    
    if label_format is not None:
        print(label_format.format(acc, numTotal, leftMean, rightMean))
    
    return (acc,float(leftMean),float(rightMean))

def EvaluateImagesForModel(label_format,cnn_model,total_imgs,total_labels,total_weights,shouldPrint=True):
    # now that we have all of the images we want, predict against them all
    predictions = cnn_model.predict(total_imgs)
    
    # we only care about the good memories and the perm memories
    correct_predictions = []
    correct_weights = []
    
    numCorrect = 0
    numTotal = len(total_labels)
    
    for i in range(0,numTotal):
        if round(predictions[i][0]) == round(total_labels[i][0]) and round(predictions[i][1]) == round(total_labels[i][1]):
            numCorrect = numCorrect + 1
        correct_predictions.append(predictions[i][0])
        correct_predictions.append(predictions[i][1])
        correct_weights.append(total_weights[i])
        correct_weights.append(total_weights[i])
            
    acc = numCorrect / numTotal
    
    if label_format is not None:
        print(label_format.format(acc, numTotal))
        
    modelRange,modelSD,modelMean,modelMedian,modelMax = histogram(correct_predictions, correct_weights, buckets=20, shouldPrint=shouldPrint)
    
    return (acc,float(modelMean),modelMax)


def ExportImageForModel(runNumber,inputImage,outputImage):
    global trainingRunNumber
    savedTrainingRunNumber = trainingRunNumber
    trainingRunNumber = runNumber
    
    if runNumber < 0:
        runNumber = 0
    
    cnn_model = model.cnn_model(True)
        
    img = images.load_single_image(inputImage)
    predictions = cnn_model.predict(img)
    
    print(predictions[0].shape)
    predictions[0].astype(np.uint8).flatten().tofile(outputImage)
    #scipy.misc.imsave(outputImage, predictions[0].flatten().reshape(30,24,3))
    
    trainingRunNumber = savedTrainingRunNumber
    
def EvaluateAllRuns():
    global trainingRunNumber
    savedTrainingRunNumber = trainingRunNumber
    ConfirmTrainingNumber()
    localMaxRuns = trainingRunNumber
    for i in range(0,localMaxRuns):
        EvaluateModelForRun(i,shouldPrint=True)
    trainingRunNumber = savedTrainingRunNumber

def EvaluateModelForRun(runNumber,shouldPrint=True):
    global trainingRunNumber
    savedTrainingRunNumber = trainingRunNumber
    trainingRunNumber = runNumber
    
    if runNumber < 0:
        runNumber = 0
    
    # generate a model we can test against
    print("Generating model for run"+str(runNumber))
    cnn_model = model.cnn_model()
    
    if os.path.isfile(ModelWeightsPath(runNumber+1)):
        print("Loading model weights from "+ModelWeightsPath(runNumber+1))
        cnn_model.load_weights(ModelWeightsPath(runNumber+1))
    
    
    # I really want to know two pieces of information:
    # 1) the accuracy of all wasted images
    # 2) the accuracy of all non-wasted images, preferably in a histogram
    
    wasted_imgs = []
    wasted_labels = []
    wasted_weights = []
    
    memories_imgs = []
    memories_labels = []
    memories_weights = []
    
    flippy_imgs = []
    flippy_labels = []
    flippy_weights = []
        
    # 1) the accuracy of all wasted images
    for i in range(0,runNumber+1):
        
        prev_imgs,prev_labels,prev_weights = GatherImagesFromTrainingRun(i, 1.0, 0, 0, 0)
        if len(prev_labels) > 0:
            flippy_imgs = np.concatenate((flippy_imgs,prev_imgs), axis=0) if len(flippy_imgs) > 0 else prev_imgs
            flippy_labels = np.concatenate((flippy_labels,prev_labels), axis=0) if len(flippy_labels) > 0 else prev_labels
            flippy_weights = np.concatenate((flippy_weights,prev_weights), axis=0) if len(flippy_weights) > 0 else prev_weights
            
            # we want to get the false positives as well...
            mask = np.zeros(len(flippy_weights), dtype=bool)
            for j in range(0,len(flippy_weights)):
                if flippy_labels[j][0] == 0 and flippy_labels[j][1] == 0:
                    mask[j] = True
            
            flippy_imgs = flippy_imgs[mask,...]
            flippy_labels = flippy_labels[mask,...]
            flippy_weights = flippy_weights[mask,...]
            
            
            
        
        prev_imgs,prev_labels,prev_weights = GatherImagesFromTrainingRun(i, 1.0, 0, -1, 0)
        if len(prev_labels) > 0:
            memories_imgs = np.concatenate((memories_imgs,prev_imgs), axis=0) if len(memories_imgs) > 0 else prev_imgs
            memories_labels = np.concatenate((memories_labels,prev_labels), axis=0) if len(memories_labels) > 0 else prev_labels
            memories_weights = np.concatenate((memories_weights,prev_weights), axis=0) if len(memories_weights) > 0 else prev_weights
        
        prev_imgs,prev_labels,prev_weights = GatherImagesFromTrainingRun(i, 1.0, -1, -1, 0)
        if len(prev_labels) > 0:
            wasted_imgs = np.concatenate((wasted_imgs,prev_imgs), axis=0) if len(wasted_imgs) > 0 else prev_imgs
            wasted_labels = np.concatenate((wasted_labels,prev_labels), axis=0) if len(wasted_labels) > 0 else prev_labels
            wasted_weights = np.concatenate((wasted_weights,prev_weights), axis=0) if len(wasted_weights) > 0 else prev_weights
    
    acc,leftMean,rightMean = EvaluateLeftAndRightMeansForModel("  Accuracy of left/right memories is {} of {} total memories: {} // {}",cnn_model,memories_imgs,memories_labels,memories_weights,shouldPrint=True)
    EvaluateImagesForModel("  Accuracy of wasted memories is {} of {} total memories",cnn_model,wasted_imgs,wasted_labels,wasted_weights,shouldPrint=False)
    
    # calculate a "flippyness" value, which is our way of detecting false positives where the AI will flip the flippers when there is no ball present
    # We can do this by testing accuracy against permanent memories and all non-wasted _0_0_0_ memories
    flippy_acc,flippy_mean,flippy_max = EvaluateImagesForModel("  Accuracy of permanent memories is {} of {} total memories",cnn_model,flippy_imgs,flippy_labels,flippy_weights,shouldPrint=False)
    if flippy_max >= flippyThreshold:
        print("")
        print("*************************************************")
        print("******* WARNING: Flippy memories detected *******")
        print("*************************************************")
        print("")
    
    
    trainingRunNumber = savedTrainingRunNumber
    
    return acc,leftMean,rightMean

def RelearnAllRunsFromScratch():
    # call Learn() for all runs in order
    global trainingRunNumber
    
    # figure out the maximum run number
    ConfirmTrainingNumber()
    
    # NOTE: we can set this to start at 1 in order to avoid retraining the base model
    for x in range(0,trainingRunNumber):
        K.clear_session()
        gc.collect()
        Learn(x)
        
def roundEdge(x, y):
    if x > 1.0-y:
        return 1.0
    if x < y:
        return 0.0
    return 0.5

def Learn(overrideRunNumber=None):
    global trainingRunNumber
        
    # figure out what run # we are on based on the existance of run# folders
    ConfirmTrainingNumber()
    
    if overrideRunNumber is not None:
        trainingRunNumber = overrideRunNumber
    
	# - memories are now stored in run# folders ( /run0/ , /run1/)
	# - new memories are stored in the max run folder
	# - when you train, only use memories from the max run folder and load the weights from the model.h5 file in that folder
	# - when a training run is complete, a new run folder is created (run#+1) and the model.h5 file is placed in there
    
    print("Begin training run "+str(trainingRunNumber))
    
    # create the model
    print("Generating the CNN model...")
    cnn_model = model.cnn_model()
                  
    #print(cnn_model.summary())
    
    
    total_imgs,total_labels,total_weights = GatherImagesFromTrainingRun(trainingRunNumber, 1.0, 0, 0, 0)
    
    if len(total_imgs) < 100:
        print("***** UNABLE TO TRAIN NOT ENOUGH MEMORIES, PLAY SOME MORE! *****")
        return
        
    didLoadWeights = False
    if os.path.isfile(ModelWeightsPath()):
        print("Loading model weights from "+ModelWeightsPath())
        cnn_model.load_weights(ModelWeightsPath())
        didLoadWeights = True
        
    msgFloat1 = 0.0
    msgFloat2 = 0.0
    msgFloat3 = 0.0
    msgFloat4 = 0.0
    
    gc.collect()
    
    # we include memories from past runs, but ideally we want the influence of runs in the far past to not influence our
    # current decisions as much.  This is representing with the normalized value supplied to the GatherImagesFromTrainingRun()
    # method, which will multpliy all loaded weights by it.
    
    minTrainingRun = trainingRunNumber-100
    
    total_imgs = []
    total_labels = []
    total_weights = []
    
     # Gather all permanent memories
    prev_imgs,prev_labels,prev_weights = GatherImagesFromTrainingRun(0, 1.0, -1, 0, -1)

    if len(prev_labels) > 0:
        print("Gathering "+str(len(prev_imgs))+" permanent memories from run0")
        total_imgs = np.concatenate((total_imgs,prev_imgs), axis=0) if len(total_imgs) > 0 else prev_imgs
        total_labels = np.concatenate((total_labels,prev_labels), axis=0) if len(total_labels) > 0 else prev_labels
        total_weights = np.concatenate((total_weights,prev_weights), axis=0) if len(total_weights) > 0 else prev_weights
        
    # Gather all normal memories from previous runs
    for i in range(minTrainingRun,trainingRunNumber+1):
        if i >= 0:
            f = (i-minTrainingRun+1) / (trainingRunNumber - minTrainingRun)
        
            # we always want to gather all of the wasted memories, because we never want to forget how we lose a
            # ball (since those memories do not get reinforced through positive reinforcement).
            
            #int(300.0*f)
            prev_imgs,prev_labels,prev_weights = GatherImagesFromTrainingRun(i, 1.0, 0, 0, -1)
        
            if len(prev_labels) > 0:
                print("Gathering "+str(len(prev_imgs))+" normal memories from run"+str(i)+" at "+str(f)+" adjustment")                  
                total_imgs = np.concatenate((total_imgs,prev_imgs), axis=0) if len(total_imgs) > 0 else prev_imgs
                total_labels = np.concatenate((total_labels,prev_labels), axis=0) if len(total_labels) > 0 else prev_labels
                total_weights = np.concatenate((total_weights,prev_weights), axis=0) if len(total_weights) > 0 else prev_weights
    
    # Now gather all of the wasted memories            
    wasted_imgs = []
    wasted_labels = []
    wasted_weights = []
    
    for i in range(0,trainingRunNumber+1):
        f = (i-minTrainingRun+1) / (trainingRunNumber - minTrainingRun)
        
        prev_imgs,prev_labels,prev_weights = GatherImagesFromTrainingRun(i, 1.0, -1, -1, 0)
        
        if len(prev_labels) > 0:
            print("Gathering "+str(len(prev_imgs))+" wasted memories from run"+str(i))
            total_imgs = np.concatenate((total_imgs,prev_imgs), axis=0) if len(total_imgs) > 0 else prev_imgs
            total_labels = np.concatenate((total_labels,prev_labels), axis=0) if len(total_labels) > 0 else prev_labels
            total_weights = np.concatenate((total_weights,prev_weights), axis=0) if len(total_weights) > 0 else prev_weights
            
            wasted_imgs = np.concatenate((wasted_imgs,prev_imgs), axis=0) if len(wasted_imgs) > 0 else prev_imgs
            wasted_labels = np.concatenate((wasted_labels,prev_labels), axis=0) if len(wasted_labels) > 0 else prev_labels
            wasted_weights = np.concatenate((wasted_weights,prev_weights), axis=0) if len(wasted_weights) > 0 else prev_weights
            
    
    wasted_acc,wasted_mean,wasted_max = EvaluateImagesForModel(None,cnn_model,wasted_imgs,wasted_labels,wasted_weights,shouldPrint=False)
        
    print("Training "+str(len(total_labels))+" images from run"+str(trainingRunNumber))
    
    # shuffle the arrays
    # t = int(time.time())
    # prng = RandomState(t)
    # prng.shuffle(total_imgs)
    # prng = RandomState(t)
    # prng.shuffle(total_labels)
    # prng = RandomState(t)
    # prng.shuffle(total_weights)
    
    
    numTrainingLoops = 24
    
    # compute the normalized weights
    normalized_weights = GenerateSampleWeights(total_labels, total_weights, 1.0 / numTrainingLoops)
    normalized_weights_local = normalized_weights[:]
    
    # note: the order of samples in the training array is completely relevant to how the AI reacts
    # - if the scoring samples are last, the AI plays more aggressive
    # - if the wasted samples are last, the AI plays more defensive
    # - in theory, if the permanent samples are first, the AI will be more flippity
    #
    # So I am adding the GenerateSampleOrdering() method to allow more fine grained control over the
    # sorted ordering of the arrays
    sampling_order = GenerateSampleOrdering(total_labels, total_weights)
    #print(sampling_order)
        
    # by reversing the sampling order we are saying the AI will favor being defensive
    indices = sampling_order.argsort()
    normalized_weights = normalized_weights[indices]
    total_imgs = total_imgs[indices]
    total_weights = total_weights[indices]
    total_labels = total_labels[indices]
    
    #print(indices)
            
    bestNumCorrect = len(total_weights) * 0.95
    
    numOfModelsToSave = 1
    while True:
        
        
        batch_size = 32
        cnn_model.fit(total_imgs, total_labels,
            batch_size=batch_size,
            epochs=1,
            shuffle=True,
            verbose=0,
            sample_weight=normalized_weights_local,
            )
        
        normalized_weights_local = normalized_weights[:]
        
        # Check to see how our model is doing, save the version with the best accuracy
        predictions = cnn_model.predict(total_imgs)
        numCorrect = 0
        isFlippy = False
        for j in range(0,len(total_weights)):
            if total_labels[j][0] == 0 and total_labels[j][1] == 0 and (
                predictions[j][0] >= flippyThreshold or predictions[j][1] >= flippyThreshold):
                isFlippy = True
            
            
            # in addition, don't overtrain the correct ones
            if round(predictions[j][0]) == total_labels[j][0] and round(predictions[j][1]) == total_labels[j][1]:
                if total_weights[j] > 0 and total_labels[j][0] == 0 and total_labels[j][1] == 0:
                    x = 1
                else:
                    if total_labels[j][0] or total_labels[j][1]:
                        m = max(predictions[j][0],predictions[j][1])
                        normalized_weights_local[j] *= (1.0 - m) * 0.75 + 0.25
                    else:
                        normalized_weights_local[j] * 0.5
                numCorrect += 1
            else:
                normalized_weights_local[j] *= 1.5
        
        if numCorrect >= bestNumCorrect and isFlippy == False:
            bestNumCorrect = numCorrect
            cnn_model.save("model.h5")
            print(" - acc: {} *saved*".format(numCorrect/len(total_weights)))
            
            numOfModelsToSave -= 1
            if numOfModelsToSave <= 0:
                break
        else:
            print(" - acc: {}".format(numCorrect/len(total_weights) ))
        
                
    '''
        # Check to see how our model is doing, save the version with the best accuracy
        predictions = cnn_model.predict(total_imgs)
        numCorrect = 0
        isFlippy = False
        for j in range(0,len(total_weights)):
            if total_weights[j] > 0 and total_labels[j][0] == 0 and total_labels[j][1] == 0 and (
                predictions[j][0] >= flippyThreshold or predictions[j][1] >= flippyThreshold):
                isFlippy = True
            
            if round(predictions[j][0]) == total_labels[j][0] and round(predictions[j][1]) == total_labels[j][1]:
                numCorrect += 1
        
        if numCorrect >= bestNumCorrect and isFlippy == False:
            bestNumCorrect = numCorrect
            cnn_model.save("model.h5")
            print(" - acc: {} *saved*".format(numCorrect/len(total_weights)))
            
            numOfModelsToSave -= 1
            if numOfModelsToSave <= 0:
                break
        else:
            print(" - acc: {}".format(numCorrect/len(total_weights) ))
            
        
        # NOTE: To allow us to train any number of images without fear of overtraining the network,
        # we first predict against our samples.  if the sample prediction is not within our expected
        # range, then we train it.  Otherwise we skip it.  We do this after every batch as this will
        # help against overtraining due to multiple similar samples in the dataset
        batch_size = 32
        for b in range(0,len(total_imgs)//batch_size):
            
            startIdx = b * batch_size
            endIdx = startIdx + batch_size
            if endIdx > len(total_imgs)-1:
                endIdx = len(total_imgs)-1
            
            total_imgs_batch = total_imgs[startIdx:endIdx]
            total_weights_batch = total_weights[startIdx:endIdx]
            normalized_weights_batch = normalized_weights[startIdx:endIdx]
            total_labels_batch = total_labels[startIdx:endIdx]
            
                        
            # get the predicted results, and adjust the normalized weights by how far off the network is
            predictions = cnn_model.predict(total_imgs_batch)
        
            # We only want to train on the images which no longer pass
            mask = np.zeros(len(total_weights_batch), dtype=bool)
            for j in range(0,len(total_weights_batch)):
                if total_weights_batch[j] == 999:
                    edge = 0.0
                elif total_weights_batch[j] < 0:
                    edge = 0.05
                elif total_labels_batch[j][0] == 0 and total_labels_batch[j][1] == 0:
                    edge = 0.0
                else:
                    edge = 0.05
            
                if roundEdge(predictions[j][0], edge) != total_labels_batch[j][0] or roundEdge(predictions[j][1], edge) != total_labels_batch[j][1]:
                    mask[j] = True
        
            total_imgs_local = total_imgs_batch[mask,...]
            normalized_weights_local = normalized_weights_batch[mask,...]
            total_labels_local = total_labels_batch[mask,...]
            
            if len(total_imgs_local) > 0:
                cnn_model.fit(total_imgs_local, total_labels_local,
                    batch_size=batch_size,
                    epochs=1,
                    shuffle=False,
                    verbose=0,
                    sample_weight=normalized_weights_local,
                    )
        '''
        
    output_labels = ['left','right','ballkicker'] 
    coreml_model = coremltools.converters.keras.convert("model.h5",input_names='image',image_input_names = 'image',class_labels = output_labels)   
    coreml_model.author = 'Rocco Bowling'   
    coreml_model.short_description = 'RL Pinball model, traing run '+str(trainingRunNumber-1)
    coreml_model.input_description['image'] = 'Image of the play area of the pinball machine'
    coreml_model.save(CoreMLPath())

    print("Conversion to coreml finished...")
    
    # move the model.h5 file into this run
    if not os.path.exists(TrainingRunPath(trainingRunNumber+1)):
        os.makedirs(TrainingRunPath(trainingRunNumber+1))
        os.makedirs(TrainingMemoryPath(trainingRunNumber+1))
        os.makedirs(WasteMemoryPath(trainingRunNumber+1))
    os.rename("model.h5", ModelWeightsPath(trainingRunNumber+1))
    
    # When we pack our model into our .msg format we can include four float variables from training
    # 1) the training number run for this model
    # 2) the mean value of left flipper histogram
    # 3) the mean value of right flipper histogram
    # 4) reserved for future use
    
    msgFloat1 = trainingRunNumber
    acc,leftMean,rightMean = EvaluateModelForRun(trainingRunNumber,shouldPrint=False)
    msgFloat2 = leftMean
    msgFloat3 = rightMean
    
    print("global accuracy", acc, "left mean", msgFloat2, "right mean", msgFloat3)
    
    f = open(ModelMessagePath(),"wb")
    f.write(struct.pack("ffff", msgFloat1, msgFloat2, msgFloat3, msgFloat4))
    f.write(read_file(CoreMLPath()))
    f.close()
    
    modelMessage = read_file(ModelMessagePath())        
    coreMLPublisher.send(modelMessage)
    
    print("Published new coreml model")
    
    # once training is finished, we need to create a new run folder and move model.h5 to it.
    trainingRunNumber = trainingRunNumber + 1
    
            
    print("Training finished...")
        
        






