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

def round2(x, y):
    if x > y:
        return 1.0
    return 0.0

def calc_predict(predictions, labels, value):
    numCorrect = 0
    for i in range(0,len(labels)):
        numCorrect += (round2(predictions[i][0], value) == round(labels[i][0]) and round2(predictions[i][1], value) == round(labels[i][1]) and round2(predictions[i][2], value) == round(labels[i][2]) and round2(predictions[i][3], value) == round(labels[i][3]))
    acc = numCorrect / len(labels)
    return acc

# used for realistic accuracy reporting during training...
class EvaluationMonitor(Callback):  
    def on_epoch_end(self, epoch, logs={}): 
        predictions = model.predict(total_imgs)
        acc = calc_predict(predictions, total_labels, 0.5)
        if acc > 0.9:
            didSaveModel = True
            print("\n saving model with accuracy of {} (total {})".format(acc, len(total_labels)))
            model.save("model.h5")
        


train_path = "/Users/rjbowli/Desktop/NASCAR_TRAINING/test/train/"
#validate_path = "/Users/rjbowli/Desktop/NASCAR_TRAINING/test/validation/"

train_max_size = 5000
#validate_max_size = 500

print("Preprocessing training images...")
train_imgs = images.generate_image_array(train_path, train_max_size)
train_labels = []

#validate_imgs = images.generate_image_array(validate_path, validate_max_size)
#validate_labels = []

images.load_images(train_imgs, train_labels, train_path, train_max_size)

print("Image Data Generator...")
datagen = ImageDataGenerator(featurewise_center=False,
                             featurewise_std_normalization=False,
                             width_shift_range=0.02,
                             height_shift_range=0.02,
                             )
                             

#i = 0
#for batch in datagen.flow(train_imgs, batch_size=1,shuffle=False,
#                          save_to_dir='preview', save_prefix='preview', save_format='png'):
#    i += 1
#    if i > 20:
#        break  # otherwise the generator would loop indefinitely

# not needed unless featurewise_center or featurewise_std_normalization or zca_whitening, which we are not.
#datagen.fit(train_imgs)


print("Generating the CNN model...")
model = model.cnn_model()

print(model.summary())

#'mean_absolute_error'
#'mean_squared_error'
model.compile(loss='binary_crossentropy',
              optimizer='rmsprop',
              metrics=['accuracy'])


#print("Preprocessing validation images...")
#images.load_images(validate_imgs, validate_labels, validate_path, validate_max_size)

#total_imgs = np.concatenate((validate_imgs,train_imgs), axis=0)
#total_labels = np.concatenate((validate_labels,train_labels), axis=0)


total_imgs = train_imgs
total_labels = train_labels

#batch_size = 1024
#batch_size = 1536
batch_size = 12
epochs = 10

           
# if we have some pre-existing weights, load those first
#if os.path.isfile("model.h5"):
#    model.load_weights("model.h5")

#(len(train_imgs) // batch_size * 4)
# let's train the model on the images inputed
clr = CyclicLR(base_lr=0.001, max_lr=0.006,
                        step_size=(len(train_imgs) // batch_size * 4), mode='exp_range',
                        gamma=0.99994)

# during training evaluations; this allows use to get per-epoch idea of how actual validation is shaping up
em = EvaluationMonitor()

# free up whatever memory we can before training
gc.collect()


# first let's train the network on high accuracy on our unaltered images
didSaveModel = False

print("Training the network stage 1...")
while didSaveModel == False:
    model.fit_generator(datagen.flow(train_imgs, train_labels, batch_size=batch_size),
                        steps_per_epoch=len(train_imgs) // batch_size,
                        epochs=epochs,
                        callbacks=[clr, em]
                        )

    model.fit(train_imgs, train_labels,
              batch_size=batch_size,
              epochs=epochs,
              shuffle=True,
              verbose=1,
              callbacks=[clr,em],
              )








