from keras.callbacks import LearningRateScheduler, ModelCheckpoint
from keras.optimizers import SGD
from keras import backend as K
import model
import images
import numpy as np
import os

print("Preprocessing all images...")
train_imgs = []
train_labels = []

validate_imgs = []
validate_labels = []

images.load_images(train_imgs, train_labels, "/Users/rjbowli/Desktop/NASCAR_TRAINING/day2/train/", 0)
train_imgs = np.array(train_imgs, dtype='float32')

images.load_images(validate_imgs, validate_labels, "/Users/rjbowli/Desktop/NASCAR_TRAINING/day2/validation/", 0)
validate_imgs = np.array(validate_imgs, dtype='float32')

print("Generating the CNN model...")
model = model.cnn_model()

# let's compile the model using SGD + momentum
lr = 0.01
#sgd = SGD(lr=lr, decay=1e-6, momentum=0.9, nesterov=True)
#model.compile(loss='categorical_crossentropy',
#              optimizer=sgd,
#              metrics=['accuracy'])


def custom_accuracy(y_true, y_pred):
    return K.cast(K.equal(K.round(y_true),K.round(y_pred)),K.floatx())

model.compile(loss='binary_crossentropy',
              optimizer='rmsprop',
              metrics=['accuracy'])
           
           
# if we have some pre-existing weights, load those first
#if os.path.isfile("model.h5"):
#    model.load_weights("model.h5")

# let's train the model on the images inputed
def lr_schedule(epoch):
    return lr * (0.1 ** int(epoch / 10))

batch_size = 16
epochs = 500

print("Training the network...")
model.fit(train_imgs, train_labels,
          batch_size=batch_size,
          epochs=epochs,
          shuffle=True,
          verbose=1,
          callbacks=[LearningRateScheduler(lr_schedule),
                     ModelCheckpoint('model.h5', save_best_only=True)],
        validation_data=(validate_imgs, validate_labels)
          )
