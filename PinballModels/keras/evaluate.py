from keras.callbacks import LearningRateScheduler, ModelCheckpoint
from skimage import io
import os
import glob
from keras.optimizers import SGD
import model
import images
import numpy as np


# Load test dataset
print("Loading evaluation images...")
validate_imgs = []
validate_labels = []

images.load_images(validate_imgs, validate_labels, "/Users/rjbowli/Desktop/NASCAR_TRAINING/day4/validation/", 0)

x_test = np.array(validate_imgs)
y_test = np.array(validate_labels)

# Load the model and install the trained weights
print("Generating the CNN model...")
model = model.cnn_model()
model.load_weights("model.h5")

# predict and evaluate
print("Performing evaluation...")
y_pred = model.predict(x_test)

#print(y_pred.shape[0])
#print(y_pred)

#print(y_test.shape[0])
#print(y_test)

numCorrect = 0
for i in range(y_test.shape[0]):
    numCorrect += (round(y_pred[i][0]) == round(y_test[i][0]) and round(y_pred[i][1]) == round(y_test[i][1]))

acc = numCorrect / y_test.shape[0]
print("numCorrect = {}".format(numCorrect))
print("total = {}".format(y_test.shape[0]))
print("Test accuracy = {}".format(acc))
