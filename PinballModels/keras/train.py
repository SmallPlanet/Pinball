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

def calc_predict(predictions, value):
    numCorrect = 0
    for i in range(0,len(validate_labels)):
        numCorrect += (round2(predictions[i][0], value) == round(validate_labels[i][0]) and round2(predictions[i][1], value) == round(validate_labels[i][1]))
    acc = numCorrect / len(validate_labels)
    print("\n ({}) prediction accuracy = {}".format(value, acc))

# used for realistic accuracy reporting during training...
class EvaluationMonitor(Callback):  
    def on_epoch_end(self, epoch, logs={}): 
        predictions = model.predict(validate_imgs)
        calc_predict(predictions, 0.000001)
        calc_predict(predictions, 0.05)
        calc_predict(predictions, 0.1)
        calc_predict(predictions, 0.2)
        calc_predict(predictions, 0.3)
        calc_predict(predictions, 0.4)
        calc_predict(predictions, 0.5)
        calc_predict(predictions, 0.6)
        calc_predict(predictions, 0.7)
        calc_predict(predictions, 0.8)
        


train_path = "/Users/rjbowli/Desktop/NASCAR_TRAINING/day7/train/"
validate_path = "/Users/rjbowli/Desktop/NASCAR_TRAINING/day7/validation/"

train_max_size = 0
validate_max_size = 0

print("Preprocessing training images...")
train_imgs = images.generate_image_array(train_path, train_max_size)
train_labels = []

validate_imgs = images.generate_image_array(validate_path, validate_max_size)
validate_labels = []

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


print("Preprocessing validation images...")
images.load_images(validate_imgs, validate_labels, validate_path, validate_max_size)


#batch_size = 1024
#batch_size = 1536
batch_size = 512
epochs = 12

           
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
print("Training the network stage 1...")
model.fit_generator(datagen.flow(train_imgs, train_labels, batch_size=batch_size),
                    steps_per_epoch=len(train_imgs) // batch_size,
                    epochs=epochs,
                    validation_data=(validate_imgs, validate_labels),
                    callbacks=[clr,
                                em,
                               ModelCheckpoint('model.stage1.{epoch:02d}-{val_acc:.3f}.h5', save_best_only=True)]
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
                     em,
                     ModelCheckpoint('model.stage2.{epoch:02d}-{val_acc:.3f}.h5', save_best_only=True)],
        validation_data=(validate_imgs, validate_labels)
          )








