from __future__ import division

from keras.callbacks import LearningRateScheduler, ModelCheckpoint, Callback
from keras.preprocessing.image import ImageDataGenerator
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

import coremltools   
import h5py
import struct
from text_histogram import histogram



# used for realistic accuracy reporting during training...
class EvaluationMonitor(Callback):  
    cnn_model = None
    imgs = []
    labels = []
    weights = []
    didSaveModel = False
    minSaveAccuracy = 0.96
    
    leftMeanSaved = 0
    leftMedianSaved = 0
    rightMeanSaved = 0
    rightMedianSaved = 0
    
    def round2(self, x, y):
        if x > y:
            return 1.0
        return 0.0

    def calc_predict(self, predictions, value):
        numCorrect = 0
        numTotal = 0
        
        # let's store the average reward value per .5 
        left_predictions = []
        left_weights = []
        right_predictions = []
        right_weights = []
        kicker_predictions = []
        kicker_weights = []
                
        # we only care about the good memories and the perm memories
        for i in range(0,len(self.labels)):            
            # average and minimum positiive predictions by class
            for j in range(0,3):
                if round(self.labels[i][j]) == 1 and self.round2(predictions[i][j], value) == round(self.labels[i][j]):
                    if j == 0:
                        left_predictions.append(predictions[i][j])
                        left_weights.append(self.weights[i])
                    if j == 1:
                        right_predictions.append(predictions[i][j])
                        right_weights.append(self.weights[i])
                    if j == 2:
                        kicker_predictions.append(predictions[i][j])
                        kicker_weights.append(self.weights[i])
            
            numCorrect += (self.round2(predictions[i][0], value) == round(self.labels[i][0]) and 
                            self.round2(predictions[i][1], value) == round(self.labels[i][1]) and 
                            self.round2(predictions[i][2], value) == round(self.labels[i][2]) )
            numTotal += 1
        
        if numTotal == 0:
            return 0
                
        acc = numCorrect / numTotal
                
        print("  - pred_acc {} of {}".format(acc, numTotal))
        
        # we want the minimum accuracy to be sufficient
        # we want the SD to be sufficient large
        if acc > self.minSaveAccuracy and len(left_predictions) > 1 and len(right_predictions) > 1:
            leftRange,leftSD,leftMean,leftMedian = histogram(left_predictions, left_weights, buckets=20)
            rightRange,rightSD,rightMean,rightMedian = histogram(right_predictions, right_weights, buckets=20)
            
            # in theory, a higher standard deviation means the network generalizes better
            if (rightSD > 0.08 and leftSD > 0.08) or (self.minSaveAccuracy == 0.0):
            #if rightSD < 0.02 and leftSD < 0.02 and rightSD > 0.01 and leftSD > 0.01:
                self.minSaveAccuracy = acc
                
                print("\n ************************* saving model! with accuracy of {} (total {})".format(acc, len(self.labels)))
                print("  - left_cutoff: {}  //  {}".format(leftMean, leftMedian))
                print("  - right_cutoff {}  //  {}".format(rightMean, rightMedian))
                
                self.leftMeanSaved = leftMean
                self.leftMedianSaved = leftMedian
                self.rightMeanSaved = rightMean
                self.rightMedianSaved = rightMedian
                
                return True
            
        return False
    
    def on_epoch_end(self, epoch, logs={}): 
        predictions = self.cnn_model.predict(self.imgs)
        if self.calc_predict(predictions, 0.5):
            self.didSaveModel = True
            self.cnn_model.save("model.h5")


print("Allocating the image data generator...")
datagen = ImageDataGenerator(featurewise_center=False,
                             featurewise_std_normalization=False,
                             width_shift_range=0.08,
                             height_shift_range=0.08,
                             )

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

def TempMemoryPath(runNumber=None):
    if runNumber == None:
        runNumber = trainingRunNumber
    return "./run" + str(runNumber) + "/tmemory/"

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

def GenerateSampleWeights(total_labels, total_weights, global_weight=1.0):
    normalized_weights = np.zeros(len(total_weights), dtype='float32')
    max_weight = max(total_weights)
    
    numWasted = 0
    numLeft = 0
    numRight = 0
    
    totalLeftWeight = 0
    totalRightWeight = 0
    
    for i in range(0,len(total_labels)):
        if total_labels[i][0] == 1:
            numLeft += 1
            totalLeftWeight += total_weights[i]
        elif total_labels[i][1] == 1:
            numRight += 1
            totalRightWeight += total_weights[i]
        else:
            numWasted += 1

    leftMod = numLeft / (numLeft + numRight)
    wastedMod = numWasted / (numLeft + numRight + numWasted)
    
    left = 0
    right = 0
    wasted = 0
    
    for i in range(0,len(total_weights)):
        
        # permanent memories are full weight always
        if total_weights[i] == 999:
            normalized_weights[i] = 1.0
        
        # wasted memories are balanced against "normal" left/right action memories
        elif total_weights[i] < 0:
            normalized_weights[i] = (1.0 - wastedMod)
            wasted += normalized_weights[i]
        else:
            # left memories are balanced against right memories, and are weighted by their own scores
            if total_labels[i][0] == 1:
                normalized_weights[i] = (total_weights[i] / totalLeftWeight * numLeft) * wastedMod * (1.0 - leftMod) * 2
                left += normalized_weights[i]
            # right memories are balanced against left memories, and are weighted by their own scores
            elif total_labels[i][1] == 1:
                normalized_weights[i] = (total_weights[i] / totalRightWeight * numRight) * wastedMod * leftMod * 2
                right += normalized_weights[i]
            # erroneous memories (false positive right/left memories manually corrected) count as a wasted memory
            else:
                normalized_weights[i] = (1.0 - wastedMod)
                wasted += normalized_weights[i]

        normalized_weights[i] *= global_weight
    
    print("wasted",wasted,"left",left,"right",right)
    
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
        
    leftRange,leftSD,leftMean,leftMedian = histogram(left_predictions, left_weights, buckets=20, shouldPrint=shouldPrint)
    rightRange,rightSD,rightMean,rightMedian = histogram(right_predictions, right_weights, buckets=20, shouldPrint=shouldPrint)
    
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
        
    modelRange,modelSD,modelMean,modelMedian = histogram(correct_predictions, correct_weights, buckets=20, shouldPrint=shouldPrint)
    
    return (acc,float(modelMean))
    
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
        
    # 1) the accuracy of all wasted images
    for i in range(0,runNumber+1):
        
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
    
    trainingRunNumber = savedTrainingRunNumber
    
    return acc,leftMean,rightMean

def RelearnAllRunsFromScratch():
    # call Learn() for all runs in order
    global trainingRunNumber
    
    # figure out the maximum run number
    ConfirmTrainingNumber()
    
    # NOTE: we can set this to start at 1 in order to avoid retraining the base model
    for x in range(1,trainingRunNumber):
        gc.collect()
        Learn(x)
        

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
    
    if len(total_imgs) < 250:
        print("***** UNABLE TO TRAIN NOT ENOUGH MEMORIES, PLAY SOME MORE! *****")
        return
    
    
    em = EvaluationMonitor()
    
    didLoadWeights = False
    if os.path.isfile(ModelWeightsPath()):
        print("Loading model weights from "+ModelWeightsPath())
        cnn_model.load_weights(ModelWeightsPath())
        didLoadWeights = True
    
    
    
    # Training here takes one of two flavors:
    # 1) this is run0 (or more appropriately, no model.h5 file exists in the current run). We should exahustively
    #    train this model as best we know how in order to get the machine intelligental playing ASAP
    #
    # 2) pre-existing weights exist and were loaded, we should lightly train this new run of data (allowing
    #    non ideal memories to be forgotten slowly over time). In theory, the number of epocs for this training
    #    should be low.        
    em.imgs = total_imgs
    em.labels = total_labels
    em.weights = total_weights
    em.cnn_model = cnn_model
    
    msgFloat1 = 0.0
    msgFloat2 = 0.0
    msgFloat3 = 0.0
    msgFloat4 = 0.0
                    
    if didLoadWeights == False:        
        epochs = 10
                                    
        # then let's train the network on the altered images
        while em.didSaveModel == False:
        
            # free up whatever memory we can before training
            gc.collect()
        
            # shuffle the arrays
            t = int(time.time())
            prng = RandomState(t)
            prng.shuffle(total_imgs)
            prng = RandomState(t)
            prng.shuffle(total_labels)
            prng = RandomState(t)
            prng.shuffle(total_weights)
        
            # make the evaluator point to the updated arrays
            em.imgs = total_imgs
            em.labels = total_labels
            em.weights = total_weights
            em.cnn_model = cnn_model
                                
            # normalize the sample weights
            normalized_weights = GenerateSampleWeights(total_labels, total_weights)
                    
            # randomize the batch size            
            batch_size = int(random.random() * 32 + 6)
        
            if batch_size > len(total_imgs):
                batch_size = len(total_imgs)
        
            # adjust the learning rate based on individual memory scores
            wlr = WeightedLR(total_weights, inversed=True)

            cnn_model.fit_generator(datagen.flow(total_imgs, total_labels, batch_size=batch_size),
                    steps_per_epoch=len(total_imgs) // batch_size,
                    epochs=epochs / 3,
                    callbacks=[wlr,em])
                
            cnn_model.fit(total_imgs, total_labels,
                      batch_size=batch_size,
                      epochs=epochs,
                      verbose=1,
                      sample_weight=normalized_weights,
                      callbacks=[em],
                      )
        
            epochs += 1
    
    else:
        
        gc.collect()
        
        # we include memories from past runs, but ideally we want the influence of runs in the far past to not influence our
        # current decisions as much.  This is representing with the normalized value supplied to the GatherImagesFromTrainingRun()
        # method, which will multpliy all loaded weights by it.
        
        minTrainingRun = trainingRunNumber-4
        
        total_imgs = []
        total_labels = []
        total_weights = []
        
        # Gather all normal memories from previous runs
        for i in range(minTrainingRun,trainingRunNumber+1):
            if i >= 0:
                f = (i-minTrainingRun+1) / (trainingRunNumber - minTrainingRun)
            
                # we always want to gather all of the wasted memories, because we never want to forget how we lose a
                # ball (since those memories do not get reinforced through positive reinforcement).
                
                #int(300.0*f)
                prev_imgs,prev_labels,prev_weights = GatherImagesFromTrainingRun(i, 1.0, 0, -1, -1)
            
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
                
        
        wasted_acc,wasted_mean = EvaluateImagesForModel(None,cnn_model,wasted_imgs,wasted_labels,wasted_weights,shouldPrint=False)
                
        normalized_weights = GenerateSampleWeights(total_labels, total_weights, 1.0 / 10.0)
        
        
        print("Training "+str(len(total_labels))+" images from run"+str(trainingRunNumber))
        done = False
        epochs = 1
        while not done:
            batch_size = 96
            cnn_model.fit(total_imgs, total_labels,
                      batch_size=batch_size,
                      epochs=10,
                      shuffle=True,
                      verbose=1,
                      sample_weight=normalized_weights,
                      )
            
            #epochs = epochs + 1
            #if epochs > 1:
            #    done = True
            
            acc,mean = EvaluateImagesForModel(None,cnn_model,total_imgs,total_labels,total_weights,shouldPrint=False)
            
            msgFloat3 = mean
            
            #if acc > 0.88:
            done = True
        
        cnn_model.save("model.h5")
    
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
        os.makedirs(TempMemoryPath(trainingRunNumber+1))
    os.rename("model.h5", ModelWeightsPath(trainingRunNumber+1))
    
    # When we pack our model into our .msg format we can include four float variables from training
    # 1) the training number run for this model
    # 2) the mean value of left flipper histogram
    # 3) the mean value of right flipper histogram
    # 4) reserved for future use
    
    msgFloat1 = trainingRunNumber
    acc,leftMean,rightMean = EvaluateModelForRun(trainingRunNumber-1,shouldPrint=False)
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
        
        






