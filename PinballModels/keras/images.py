import numpy as np
from keras import backend as K
from keras.preprocessing.image import load_img, img_to_array, array_to_img
import os
import glob

NUM_CLASSES = 2
IMG_SIZE = [169,120]

K.set_image_data_format('channels_last')

maskImg = img_to_array(load_img("mask.png", grayscale=True, target_size=[300,169]))
maskImg = maskImg[180:300,0:169]

def preprocess_img(img):
    # rescale to standard size
    #img = transform.resize(img, (IMG_SIZE[1], IMG_SIZE[0]), mode='constant')    
    img = img[180:300,0:169]
    
    # mask out the lights...
    for i in range(img.shape[0]):
        for j in range(img[i].shape[0]):
            if maskImg[i][j] < 128:
                img[i][j] = 0
        
    return img

def get_labels(img_path):
    filename = img_path.split('/')[-1]
    buttons = filename.split('_')
    retVal = [int(buttons[0]),int(buttons[1])]
    return retVal

def load_images(imgs, labels, dir_path, max_size):
    all_img_paths = glob.glob(os.path.join(dir_path, '*.jpg'))
    np.random.shuffle(all_img_paths)
    for img_path in all_img_paths:
        img = preprocess_img(img_to_array(load_img(img_path, grayscale=True, target_size=[300,IMG_SIZE[0]])))
        imgs.append(img)
        labels.append(get_labels(img_path))
        if max_size != 0 and len(labels) > max_size:
            return
