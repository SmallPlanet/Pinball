import numpy as np
from keras import backend as K
from keras.preprocessing.image import load_img, img_to_array, array_to_img
import os
import glob
import gc

NUM_CLASSES = 3
IMG_SIZE = [48*2,120,3]

K.set_image_data_format('channels_last')

def get_score(img_path):
    filename = img_path.split('/')[-1]
    buttons = filename.split('_')
    return int(buttons[0])

def get_labels_and_score(img_path):
    filename = img_path.split('/')[-1]
    buttons = filename.split('_')
    retVal = [float(buttons[0]),float(buttons[1]),float(buttons[2]),float(buttons[3])]
    return retVal

def get_labels(img_path):
    filename = img_path.split('/')[-1]
    buttons = filename.split('_')
    retVal = [float(buttons[1]),float(buttons[2]),float(buttons[3])]
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

def load_single_image(img_path):
    imgs = np.zeros((1, IMG_SIZE[1], IMG_SIZE[0], IMG_SIZE[2]), dtype='float32')
    img = img_to_array(load_img(img_path, grayscale=(IMG_SIZE[2] == 1), target_size=[IMG_SIZE[1],IMG_SIZE[0]]))
    np.copyto(imgs[0],img)
    return imgs

def load_images(imgs, labels, weights, dir_path, max_size):
    all_img_paths = glob.glob(os.path.join(dir_path, '*.jpg'))
    np.random.shuffle(all_img_paths)
    n = 0
    for img_path in all_img_paths:
        if n % 10000 == 1:
            gc.collect()
        load_image(n, imgs, labels, weights, img_path)
        n = n + 1
        if max_size != 0 and len(labels) >= max_size:
            return
