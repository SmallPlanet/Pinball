from keras.models import Sequential
from keras.layers.core import Dense, Dropout, Activation, Flatten
from keras.layers.convolutional import Conv2D
from keras.layers.pooling import MaxPooling2D
from keras.optimizers import SGD
from keras.layers.normalization import BatchNormalization
import images

def cnn_model(justTheImage=False):
    
    model = Sequential()

    model.add(Conv2D(8, strides=2, kernel_size=3, input_shape=(images.IMG_SIZE[1], images.IMG_SIZE[0], images.IMG_SIZE[2])))
    model.add(Activation('elu'))
    
    model.add(Conv2D(16, kernel_size=3))
    model.add(Activation('elu'))
    
    if justTheImage == False:
        model.add(Flatten())
        model.add(Dense(64))
        model.add(Activation('elu'))
        model.add(BatchNormalization())
        model.add(Dense(images.NUM_CLASSES))
        model.add(Activation('sigmoid'))
    
    print(model.summary())
    
    model.compile(loss='binary_crossentropy',
                  optimizer='rmsprop',
                  metrics=['accuracy'])
    
    return model


