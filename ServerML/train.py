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
    minSaveAccuracy = 0.98
    
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
            if (rightSD > 0.1 and leftSD > 0.1) or (self.minSaveAccuracy == 0.0):
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

def GenerateClassWeights(total_labels):
    class_weight_dict = {0:1,1:1,2:1,3:1}
    for i in range(0,len(total_labels)):
        class_weight_dict[0] += total_labels[i][0]
        class_weight_dict[1] += total_labels[i][1]
        class_weight_dict[2] += total_labels[i][2]
    
    class_max_weight = max(class_weight_dict.values())

    if class_max_weight != 0:
        class_weight_dict[0] /= class_max_weight
        class_weight_dict[1] /= class_max_weight
        class_weight_dict[2] /= class_max_weight
    
    return class_weight_dict

def GenerateSampleWeights(total_weights):
    normalized_weights = np.zeros(len(total_weights), dtype='float32')
    max_weight = max(total_weights)
    for i in range(0,len(total_weights)):
        if total_weights[i] == 999:
            normalized_weights[i] = 1.0
        else:
            normalized_weights[i] = total_weights[i] / max_weight
            if normalized_weights[i] < 0:
                #normalized_weights[i] = normalized_weights[i] * -1.0
                normalized_weights[i] = 1.0

def ConfirmTrainingNumber():
    global trainingRunNumber
    
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


def GatherImagesFromTrainingRun(runNumber,maxImages):
    train_imgs = images.generate_image_array(TrainingMemoryPath(runNumber), maxImages)
    train_labels = []
    train_weights = []
    images.load_images(train_imgs, train_labels, train_weights, TrainingMemoryPath(runNumber), maxImages)
    
    permanent_imgs = images.generate_image_array(PermanentMemoryPath(), maxImages)
    permanent_labels = []
    permanent_weights = []
    images.load_images(permanent_imgs, permanent_labels, permanent_weights, PermanentMemoryPath(), maxImages)
        
    waste_imgs = images.generate_image_array(WasteMemoryPath(runNumber), maxImages)
    waste_labels = []
    waste_weights = []
    images.load_images(waste_imgs, waste_labels, waste_weights, WasteMemoryPath(runNumber), maxImages)
    
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
    
        

def Learn():
    global trainingRunNumber
    
    # figure out what run # we are on based on the existance of run# folders
    ConfirmTrainingNumber()
    
	# - memories are now stored in run# folders ( /run0/ , /run1/)
	# - new memories are stored in the max run folder
	# - when you train, only use memories from the max run folder and load the weights from the model.h5 file in that folder
	# - when a training run is complete, a new run folder is created (run#+1) and the model.h5 file is placed in there
    
    print("Begin training run "+str(trainingRunNumber))
    
    # create the model
    print("Generating the CNN model...")
    cnn_model = model.cnn_model()

    cnn_model.compile(loss='binary_crossentropy',
                  optimizer='rmsprop',
                  metrics=['accuracy'])
    
    
    total_imgs,total_labels,total_weights = GatherImagesFromTrainingRun(trainingRunNumber, 0)
        
    if len(total_imgs) >= 32:
        
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
            
                # take into account the weight of classes
                class_weight_dict = GenerateClassWeights(total_labels)
                        
                # normalize the sample weights
                normalized_weights = GenerateSampleWeights(total_weights)
                        
                # randomize the batch size            
                batch_size = int(random.random() * 32 + 6)
            
                if batch_size > len(total_imgs):
                    batch_size = len(total_imgs)
            
                # adjust the learning rate based on individual memory scores
                wlr = WeightedLR(total_weights, inversed=True)

                cnn_model.fit_generator(datagen.flow(total_imgs, total_labels, batch_size=batch_size),
                        steps_per_epoch=len(total_imgs) // batch_size,
                        epochs=epochs / 3,
                        class_weight=class_weight_dict,
                        callbacks=[wlr,em])
                    
                cnn_model.fit(total_imgs, total_labels,
                          batch_size=batch_size,
                          epochs=epochs,
                          verbose=1,
                          class_weight=class_weight_dict,
                          sample_weight=normalized_weights,
                          callbacks=[em],
                          )
            
                epochs += 1
        
        else:
            
            
            batch_size = 32
            
            # we need to train on random samples of previous runs to help the AI generalize well and
            # not forget too much
            for i in range(0,trainingRunNumber):
                prev_imgs,prev_labels,prev_weights = GatherImagesFromTrainingRun(i, 48)
                
                # take into account the weight of classes
                class_weight_dict = GenerateClassWeights(prev_labels)
                    
                # normalize the sample weights
                normalized_weights = GenerateSampleWeights(prev_weights)
                
                print("Retraining "+str(len(prev_labels))+" images from run"+str(i))
                cnn_model.fit(prev_imgs, prev_labels,
                          batch_size=batch_size,
                          epochs=3,
                          verbose=1,
                          #class_weight=class_weight_dict,
                          sample_weight=normalized_weights,
                          callbacks=[],
                          )
                
                
            
            
            # take into account the weight of classes
            class_weight_dict = GenerateClassWeights(total_labels)
                    
            # normalize the sample weights
            normalized_weights = GenerateSampleWeights(total_weights)
            
            print("Training "+str(len(total_labels))+" images from run"+str(trainingRunNumber))
            cnn_model.fit(total_imgs, total_labels,
                      batch_size=batch_size,
                      epochs=15,
                      verbose=1,
                      #class_weight=class_weight_dict,
                      sample_weight=normalized_weights,
                      callbacks=[],
                      )
                
            cnn_model.save("model.h5")
        
        output_labels = ['left','right','ballkicker'] 
        coreml_model = coremltools.converters.keras.convert("model.h5",input_names='image',image_input_names = 'image',class_labels = output_labels)   
        coreml_model.author = 'Rocco Bowling'   
        coreml_model.short_description = 'RL Pinball model, traing run '+str(trainingRunNumber-1)
        coreml_model.input_description['image'] = 'Image of the play area of the pinball machine'
        coreml_model.save(CoreMLPath())

        print("Conversion to coreml finished...")
        
        f = open(ModelMessagePath(),"wb")
        f.write(struct.pack("ffff", em.leftMeanSaved, em.leftMedianSaved, em.rightMeanSaved, em.rightMedianSaved))
        f.write(read_file(CoreMLPath()))
        f.close()
        
        modelMessage = read_file(ModelMessagePath())        
        coreMLPublisher.send(modelMessage)
        
        print("Published new coreml model")
        
        # once training is finished, we need to create a new run folder and move model.h5 to it.
        trainingRunNumber = trainingRunNumber + 1
        if not os.path.exists(TrainingRunPath()):
            os.makedirs(TrainingRunPath())
            os.makedirs(TrainingMemoryPath())
            os.makedirs(WasteMemoryPath())
            os.makedirs(TempMemoryPath())
        
        # move the model.h5 file into this run
        os.rename("model.h5", ModelWeightsPath())
        
        print("Training finished...")
        
        






