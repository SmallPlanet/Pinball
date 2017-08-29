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

# used for realistic accuracy reporting during training...
class EvaluationMonitor(Callback): 
    def on_epoch_end(self, epoch, logs={}): 
        predictions = model.predict(validate_imgs)
        numCorrect = 0
        for i in range(validate_labels_as_np.shape[0]):
            numCorrect += (round(predictions[i][0]) == round(validate_labels_as_np[i][0]) and round(predictions[i][1]) == round(validate_labels_as_np[i][1]))
        acc = numCorrect / validate_labels_as_np.shape[0]
        print("\nprediction accuracy = {}".format(acc))


train_path = "/Users/rjbowli/Desktop/NASCAR_TRAINING/day4/train/"
validate_path = "/Users/rjbowli/Desktop/NASCAR_TRAINING/day4/validation/"

print("Preprocessing training images...")
train_imgs = images.generate_image_array(train_path)
train_labels = []

validate_imgs = images.generate_image_array(validate_path)
validate_labels = []

images.load_images(train_imgs, train_labels, train_path, 0)

print("Image Data Generator...")
datagen = ImageDataGenerator(featurewise_center=False,
                             featurewise_std_normalization=False,
                             width_shift_range=0.1,
                             height_shift_range=0.1,
                             zoom_range=0.0,
                             shear_range=0.0,
                             rotation_range=5.0)

# not needed unless featurewise_center or featurewise_std_normalization or zca_whitening, which we are not.
#datagen.fit(train_imgs)


print("Generating the CNN model...")
model = model.cnn_model()

print(model.summary())

model.compile(loss='binary_crossentropy',
              optimizer='rmsprop',
              metrics=['accuracy'])


print("Preprocessing validation images...")
images.load_images(validate_imgs, validate_labels, validate_path, 0)
validate_labels_as_np = np.array(validate_labels)


batch_size = 512
epochs = 15

           
# if we have some pre-existing weights, load those first
#if os.path.isfile("model.h5"):
#    model.load_weights("model.h5")

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
                               ModelCheckpoint('model.h5', save_best_only=True)]
                    )


# then let's train the network on the altered images
print("Training the network stage 2...")
model.fit(train_imgs, train_labels,
          batch_size=batch_size,
          epochs=epochs,
          shuffle=True,
          verbose=1,
          callbacks=[clr,
                     em,
                     ModelCheckpoint('model.h5', save_best_only=True)],
        validation_data=(validate_imgs, validate_labels)
          )



