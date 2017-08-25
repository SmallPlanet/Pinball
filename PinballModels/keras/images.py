import numpy as np
from keras import backend as K
from keras.preprocessing.image import load_img, img_to_array, array_to_img
import os
import glob
import gc

NUM_CLASSES = 2
IMG_SIZE = [169,120]

K.set_image_data_format('channels_last')

def preprocess_img(img):
    return img

def get_labels(img_path):
    filename = img_path.split('/')[-1]
    buttons = filename.split('_')
    retVal = [int(buttons[0]),int(buttons[1])]
    return retVal
    
def load_image(imgs, labels, img_path):
    img = preprocess_img(img_to_array(load_img(img_path, grayscale=False, target_size=[IMG_SIZE[1],IMG_SIZE[0]])))
    imgs.append(img)
    labels.append(get_labels(img_path))

def load_images(imgs, labels, dir_path, max_size):
    all_img_paths = glob.glob(os.path.join(dir_path, '*.jpg'))
    np.random.shuffle(all_img_paths)
    n = 0
    for img_path in all_img_paths:
        n = n + 1
        if n % 10000 == 1:
            gc.collect()
            print(n)
        load_image(imgs, labels,img_path)
        if max_size != 0 and len(labels) > max_size:
            return
