from __future__ import division

from keras.callbacks import LearningRateScheduler, ModelCheckpoint, Callback
from keras.preprocessing.image import ImageDataGenerator
from keras.optimizers import SGD
from keras import backend as K
from clr_callback import CyclicLR
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
    imgs = []
    labels = []
    didSaveModel = False
    minSaveAccuracy = 0.95
    
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
        predictions = model.predict(self.imgs)
        acc = self.calc_predict(predictions, 0.5)
        if acc > self.minSaveAccuracy:
            self.minSaveAccuracy = acc
            print("\n saving model with accuracy of {} (total {})".format(acc, len(self.labels)))
            self.didSaveModel = True
            model.save("model.h5")




batch_size = 12
epochs = 10

permanent_path = "./pmemory/"
permanent_max_size = 0

train_path = "./memory/"
train_max_size = 0

waste_path = "./waste/"
waste_max_size = 0

# create the model
print("Generating the CNN model...")
model = model.cnn_model()

model.compile(loss='binary_crossentropy',
              optimizer='rmsprop',
              metrics=['accuracy'])

# if we have some pre-existing weights, load those first
if os.path.isfile("model.h5"):
    print("Loading previous model weights...")
    model.load_weights("model.h5")

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

    print("Loadinf long term memories...")
    train_imgs = images.generate_image_array(train_path, train_max_size)
    train_labels = []
    
    images.load_images(train_imgs, train_labels, train_path, train_max_size)
    
    print("Load permanent memories...")
    permanent_imgs = images.generate_image_array(permanent_path, permanent_max_size)
    permanent_labels = []
    
    images.load_images(permanent_imgs, permanent_labels, permanent_path, permanent_max_size)
    
    print("Load wasted memories...")
    waste_max_size = len(train_imgs)//3
    waste_imgs = images.generate_image_array(waste_path, waste_max_size)
    waste_labels = []
    
    images.load_images(waste_imgs, waste_labels, waste_path, waste_max_size)
    
    if len(train_labels) > 0 and len(waste_labels) > 0:
        total_imgs = np.concatenate((permanent_imgs,train_imgs,waste_imgs), axis=0)
        total_labels = np.concatenate((permanent_labels,train_labels,waste_labels), axis=0)
    elif len(train_labels) > 0:
        total_imgs = np.concatenate((permanent_imgs,train_imgs), axis=0)
        total_labels = np.concatenate((permanent_labels,train_labels), axis=0)
    elif len(waste_labels) > 0:
        total_imgs = np.concatenate((permanent_imgs,waste_imgs), axis=0)
        total_labels = np.concatenate((permanent_labels,waste_labels), axis=0)
    else:
        total_imgs = permanent_imgs
        total_labels = permanent_labels
    
                    
    if len(total_imgs) >= 6:
        
        #if os.path.isfile("model.h5"):
        #    print("Loading previous model weights...")
        #    model.load_weights("model.h5")
                                        
        em = EvaluationMonitor()
        em.imgs = total_imgs
        em.labels = total_labels

        # then let's train the network on the altered images
        print("Training the long term memories...")
        while em.didSaveModel == False:
            
            # free up whatever memory we can before training
            gc.collect()
            
            batch_size = int(random.random() * 32 + 6)
            
            if batch_size > len(total_imgs):
                batch_size = len(total_imgs)
            
            # cyclic learning rate
            clr = CyclicLR(base_lr=0.001, max_lr=0.006,
                                    step_size=(len(permanent_imgs) // batch_size * 4), mode='exp_range',
                                    gamma=0.99994)
            
            model.fit_generator(datagen.flow(total_imgs, total_labels, batch_size=batch_size),
                    steps_per_epoch=len(total_imgs) // batch_size,
                    epochs=epochs,
                    callbacks=[clr,em])
                    
            model.fit(total_imgs, total_labels,
                      batch_size=batch_size,
                      epochs=epochs,
                      shuffle=True,
                      verbose=1,
                      callbacks=[clr,em],
                      )
                
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
        
        






