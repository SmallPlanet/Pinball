import train
import os
import glob
import blur
import images
import numpy as np
from keras.preprocessing.image import load_img, img_to_array, array_to_img


train.Learn()


def TestBlurryImages():
    # test blurry image code...
    all_img_paths = glob.glob(os.path.join("blurry", '*.jpg'))
    for img_path in all_img_paths:
        jpg = np.fromfile(img_path, dtype='float32')
        isBlurry = blur.IsBlurryJPEG(jpg, cutoff=3000)
        print(isBlurry, img_path)

#TestBlurryImages()