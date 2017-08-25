from keras.models import Sequential
from keras.layers.core import Dense, Dropout, Activation, Flatten
from keras.layers.convolutional import Conv2D
from keras.layers.pooling import MaxPooling2D
from keras.optimizers import SGD
from keras.layers.normalization import BatchNormalization
import images

def cnn_model():
    #model = Sequential()

    #model.add(Conv2D(32, (3, 3), padding='same',
    #                 input_shape=(images.IMG_SIZE[1], images.IMG_SIZE[0], 3),
    #                 activation='relu'))
    #model.add(BatchNormalization())
    #model.add(Conv2D(32, (3, 3), activation='relu'))
    #model.add(MaxPooling2D(pool_size=(2, 2)))
    #model.add(Dropout(0.2))

    #model.add(BatchNormalization())
    #model.add(Conv2D(64, (3, 3), padding='same', activation='relu'))
    #model.add(BatchNormalization())
    #model.add(Conv2D(64, (3, 3), activation='relu'))
    #model.add(MaxPooling2D(pool_size=(2, 2)))
    #model.add(Dropout(0.2))

    #model.add(BatchNormalization())
    #model.add(Conv2D(128, (3, 3), padding='same', activation='relu'))
    #model.add(BatchNormalization())
    #model.add(Conv2D(128, (3, 3), activation='relu'))
    #model.add(MaxPooling2D(pool_size=(2, 2)))
    #model.add(Dropout(0.2))

    #model.add(Flatten())
    #model.add(BatchNormalization())
    #model.add(Dense(512, activation='relu'))
    #model.add(Dropout(0.5))
    #model.add(BatchNormalization())
    #model.add(Dense(images.NUM_CLASSES, activation='softmax'))
    
    
    model = Sequential()
    model.add(Conv2D(1, kernel_size=3, input_shape=(images.IMG_SIZE[1], images.IMG_SIZE[0], 3)))
    model.add(Activation('relu'))
    model.add(MaxPooling2D(pool_size=(2, 2)))
    
    model.add(Conv2D(1, kernel_size=3))
    model.add(Activation('relu'))
    model.add(MaxPooling2D(pool_size=(2, 2)))

    model.add(Flatten())
    model.add(Dense(128))
    model.add(BatchNormalization())
    model.add(Activation('relu'))
    model.add(Dropout(0.5))
    model.add(Dense(images.NUM_CLASSES))
    model.add(Activation('sigmoid'))
    
    return model


