from __future__ import division

import templateMatch
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




def TestBallMatching(path):
    # test blurry image code...
    all_img_paths = glob.glob(os.path.join(path, '*.jpg'))
    numCorrect = 0
    numTotal = 0
    for img_path in all_img_paths:
        jpg = np.fromfile(img_path, dtype='float32')
        hasBall = templateMatch.ContainsAtLeatOneBall(jpg)
        
        if os.path.basename(img_path).startswith("999_0_0_0_") == True and hasBall == False:
            numCorrect += 1
        elif os.path.basename(img_path).startswith("999_0_0_0_") == False and hasBall == True:
            numCorrect += 1
        else:
            print("Bad Match:", hasBall, img_path)
            
        numTotal = numTotal + 1
    
    print("accuracy: ", (numCorrect / numTotal) * 100)

#TestBallMatching("pmemory")
#TestBallMatching("memory")
#TestBallMatching("waste")
