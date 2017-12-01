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

import coremltools   
import h5py




# used for realistic accuracy reporting during training...
class EvaluationMonitor(Callback):  
    cnn_model = None
    imgs = []
    labels = []
    didSaveModel = False
    minSaveAccuracy = 0.97
    
    def round2(self, x, y):
        if x > y:
            return 1.0
        return 0.0

    def calc_predict(self, predictions, value):
        numCorrect = 0
        for i in range(0,len(self.labels)):
            numCorrect += (self.round2(predictions[i][0], value) == round(self.labels[i][0]) and 
                            self.round2(predictions[i][1], value) == round(self.labels[i][1]) and 
                            self.round2(predictions[i][2], value) == round(self.labels[i][2]) and
                            self.round2(predictions[i][3], value) == round(self.labels[i][3]))
        acc = numCorrect / len(self.labels)
        return acc
    
    def on_epoch_end(self, epoch, logs={}): 
        predictions = self.cnn_model.predict(self.imgs)
        acc = self.calc_predict(predictions, 0.5)
        print("  - pred_acc {}".format(acc))
        if acc > self.minSaveAccuracy:
            self.minSaveAccuracy = acc
            print("\n saving model with accuracy of {} (total {})".format(acc, len(self.labels)))
            self.didSaveModel = True
            self.cnn_model.save("model.h5")




permanent_path = "./pmemory/"
permanent_max_size = 0

train_path = "./memory/"
train_max_size = 0

waste_path = "./waste/"
waste_max_size = 0

# if we have some pre-existing weights, load those first
#if os.path.isfile("model.h5"):
#    print("Loading previous model weights...")
#    model.load_weights("model.h5")

print("Allocating the image data generator...")
datagen = ImageDataGenerator(featurewise_center=False,
                             featurewise_std_normalization=False,
                             width_shift_range=0.04,
                             height_shift_range=0.04,
                             )

coreMLPublisher = comm.publisher(comm.endpoint_pub_CoreMLUpdates)

def read_file(path):
    with open(path, 'rb') as f:
        return f.read()

def Learn():
    
    # create the model
    print("Generating the CNN model...")
    cnn_model = model.cnn_model()

    cnn_model.compile(loss='binary_crossentropy',
                  optimizer='rmsprop',
                  metrics=['accuracy'])
    
    print("Loading long term memories...")
    train_imgs = images.generate_image_array(train_path, train_max_size)
    train_labels = []
    train_weights = []
    
    images.load_images(train_imgs, train_labels, train_weights, train_path, train_max_size)
    
    print("Load permanent memories...")
    permanent_imgs = images.generate_image_array(permanent_path, permanent_max_size)
    permanent_labels = []
    permanent_weights = []
    
    images.load_images(permanent_imgs, permanent_labels, permanent_weights, permanent_path, permanent_max_size)
    
                    
    if len(permanent_imgs) + len(train_imgs) >= 6:
        
        #if os.path.isfile("model.h5"):
        #    print("Loading previous model weights...")
        #    cnn_model.load_weights("model.h5")
        
        em = EvaluationMonitor()
        
        waste_max_size = len(train_imgs)//6
        waste_imgs = images.generate_image_array(waste_path, waste_max_size)
        
        epochs = 10
                                        
        # then let's train the network on the altered images
        print("Training the long term memories...")
        while em.didSaveModel == False:
            
            # load a new set of wasted images each time through the training loop
            print("Reload new wasted memories...")
            waste_labels = []
            waste_weights = []
    
            images.load_images(waste_imgs, waste_labels, waste_weights, waste_path, waste_max_size)
    
            if len(train_labels) > 0 and len(waste_labels) > 0:
                total_imgs = np.concatenate((permanent_imgs,train_imgs,waste_imgs), axis=0)
                total_labels = np.concatenate((permanent_labels,train_labels,waste_labels), axis=0)
                total_weights = np.concatenate((permanent_weights,train_weights,waste_weights), axis=0)
            elif len(train_labels) > 0:
                total_imgs = np.concatenate((permanent_imgs,train_imgs), axis=0)
                total_labels = np.concatenate((permanent_labels,train_labels), axis=0)
                total_weights = np.concatenate((permanent_weights,train_weights), axis=0)
            elif len(waste_labels) > 0:
                total_imgs = np.concatenate((permanent_imgs,waste_imgs), axis=0)
                total_labels = np.concatenate((permanent_labels,waste_labels), axis=0)
                total_weights = np.concatenate((permanent_weights,waste_weights), axis=0)
            else:
                total_imgs = permanent_imgs
                total_labels = permanent_labels
                total_weights = permanent_weights
                
            
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
            em.cnn_model = cnn_model
            
            
            # take into account the weight of classes
            class_weight_dict = {0:0,1:0,2:0,3:0}
            for i in range(0,len(total_labels)):
                class_weight_dict[0] += total_labels[i][0]
                class_weight_dict[1] += total_labels[i][1]
                class_weight_dict[2] += total_labels[i][2]
                class_weight_dict[3] += total_labels[i][3]
                
            max_weight = max(class_weight_dict.values())
            
            class_weight_dict[0] /= max_weight
            class_weight_dict[1] /= max_weight
            class_weight_dict[2] /= max_weight
            class_weight_dict[3] /= max_weight
            
            
            # randomize the batch size            
            batch_size = int(random.random() * 32 + 6)
            
            if batch_size > len(total_imgs):
                batch_size = len(total_imgs)
            
            # adjust the learning rate based on individual memory scores
            wlr = WeightedLR(total_weights)

            cnn_model.fit_generator(datagen.flow(total_imgs, total_labels, batch_size=batch_size),
                    steps_per_epoch=len(total_imgs) // batch_size,
                    epochs=epochs / 2,
                    class_weight=class_weight_dict,
                    callbacks=[wlr,em])
                    
            cnn_model.fit(total_imgs, total_labels,
                      batch_size=batch_size,
                      epochs=epochs,
                      verbose=1,
                      class_weight=class_weight_dict,
                      callbacks=[wlr,em],
                      )
            
            epochs += 1
                
        print("Training finished...")
        
        output_labels = ['left','right','start','ballkicker'] 
        coreml_model = coremltools.converters.keras.convert('model.h5',input_names='image',image_input_names = 'image',class_labels = output_labels)   
        coreml_model.author = 'Rocco Bowling'   
        coreml_model.short_description = 'RL Pinball model'
        coreml_model.input_description['image'] = 'Image of the play area of the pinball machine'
        coreml_model.save('pinballModel.mlmodel')

        print("Conversion to coreml finished...")
        
        
        modelBytes = read_file("pinballModel.mlmodel")        
        coreMLPublisher.send(modelBytes)
        
        print("Published new coreml model")
        
        






