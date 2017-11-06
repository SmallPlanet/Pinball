import numpy as np
from keras import backend as K
from keras.preprocessing.image import load_img, img_to_array, array_to_img
import os
import glob
import gc

NUM_CLASSES = 4
IMG_SIZE = [160,80,1]

K.set_image_data_format('channels_last')

def get_score(img_path):
    filename = img_path.split('/')[-1]
    buttons = filename.split('_')
    return int(buttons[0])

def get_labels_and_score(img_path):
    filename = img_path.split('/')[-1]
    buttons = filename.split('_')
    retVal = [int(buttons[0]),int(buttons[1]),int(buttons[2]),int(buttons[3]),int(buttons[4])]
    return retVal

def get_labels(img_path):
    filename = img_path.split('/')[-1]
    buttons = filename.split('_')
    retVal = [int(buttons[1]),int(buttons[2]),int(buttons[3]),int(buttons[4])]
    return retVal

def generate_image_array(dir_path, max_size):
    all_img_paths = glob.glob(os.path.join(dir_path, '*.jpg'))
    size = len(all_img_paths)
    if max_size != 0 and size > max_size:
        size = max_size
    return np.zeros((size, IMG_SIZE[1], IMG_SIZE[0], IMG_SIZE[2]), dtype='float32')

def load_image(imgs_idx, imgs, labels, weights, img_path):
    img = img_to_array(load_img(img_path, grayscale=(IMG_SIZE[2] == 1), target_size=[IMG_SIZE[1],IMG_SIZE[0]]))
    np.copyto(imgs[imgs_idx],img)
    
    labels.append(get_labels(img_path))
    weights.append(get_score(img_path))
    return imgs_idx

def load_images(imgs, labels, weights, dir_path, max_size):
    all_img_paths = glob.glob(os.path.join(dir_path, '*.jpg'))
    np.random.shuffle(all_img_paths)
    n = 0
    for img_path in all_img_paths:
        if n % 10000 == 1:
            gc.collect()
            print(n)
        load_image(n, imgs, labels, weights, img_path)
        n = n + 1
        if max_size != 0 and len(labels) >= max_size:
            return
