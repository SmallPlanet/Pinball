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

batch_size = 64
epochs = 3

train_path = "./memory/"
train_max_size = 0

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
                             width_shift_range=0.02,
                             height_shift_range=0.02,
                             )

def Learn():

    print("Load random selection of memories...")
    train_imgs = images.generate_image_array(train_path, train_max_size)
    train_labels = []
    
    # cyclic learning rate
    clr = CyclicLR(base_lr=0.001, max_lr=0.006,
                            step_size=(len(train_imgs) // batch_size * 4), mode='exp_range',
                            gamma=0.99994)
    
    images.load_images(train_imgs, train_labels, train_path, train_max_size)

    # free up whatever memory we can before training
    gc.collect()

    # first let's train the network on high accuracy on our unaltered images
    print("Training the network stage 1...")
    model.fit_generator(datagen.flow(train_imgs, train_labels, batch_size=batch_size),
                        steps_per_epoch=len(train_imgs) // batch_size,
                        epochs=epochs,
                        callbacks=[clr,
                                   ModelCheckpoint('model.h5', save_best_only=True)]
                        )
    #model.{epoch:02d}-{val_loss:.2f}.h5


    # then let's train the network on the altered images
    print("Training the network stage 2...")
    model.fit(train_imgs, train_labels,
              batch_size=batch_size,
              epochs=epochs,
              shuffle=True,
              verbose=1,
              callbacks=[clr,
                         ModelCheckpoint('model.h5', save_best_only=True)],
              )
    
    print("Training finished.")







