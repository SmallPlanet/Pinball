from __future__ import division
from PIL import Image
import numpy as np
from keras.preprocessing.image import load_img, img_to_array, array_to_img

import sys
import train
import model
import images
import imageio


def ExportAnimatedHeatmapForAllImages(outputPath):
    images = []
    
    savedTrainingRunNumber = train.trainingRunNumber
    
    maxTrainingRun = train.ConfirmTrainingNumber()
    for runNumber in range(0,maxTrainingRun):
        images.append(imageio.imread(train.HeatmapPath(runNumber)))
    
    # add a few more at the end so there is a pause before it loops
    images.append(imageio.imread(train.HeatmapPath(maxTrainingRun-1)))
    images.append(imageio.imread(train.HeatmapPath(maxTrainingRun-1)))
    images.append(imageio.imread(train.HeatmapPath(maxTrainingRun-1)))
    images.append(imageio.imread(train.HeatmapPath(maxTrainingRun-1)))
    
    imageio.mimsave(outputPath, images, duration=0.5)
    
    train.trainingRunNumber = savedTrainingRunNumber

def ExportHeatmapForModel(runNumber, outputPath):
    
    # 0. Load the base image
    baseImg = Image.open('resources/heatmap_base.jpg', 'r')
    img_w, img_h = baseImg.size
    basePix = baseImg.load()
    
    # 1. Load the ball image
    ballImg = Image.open('resources/heatmap_ball.png', 'r')
    ball_w, ball_h = ballImg.size
    
    # 2. Create the scratch image
    scratchImg = Image.new('RGB', (img_w, img_h), (255, 255, 255, 255))
        
    # 3. Create the heat map
    heatmapImg = Image.new('RGB', (img_w//2, img_h), (255, 255, 255, 255))
    heatmapPix = heatmapImg.load()
    
    # 4. load the model
    cnn_model = model.cnn_model()
    cnn_model.load_weights(train.ModelWeightsPath(runNumber+1))
    
    # 5. prepare a numpy img to send to our model
    scratchNP = np.zeros((1, img_h, img_w, 3), dtype='float32')
    
    print("Generating heatmap:")
    for x in range(0,img_w//2):
        sys.stdout.write('.')
        sys.stdout.flush()
        for y in range(0,img_h):
            scratchImg.paste(baseImg, (0,0))
            scratchImg.paste(ballImg, (x-ball_w//2,y-ball_h//2), ballImg)
            scratchImg.paste(ballImg, (x-ball_w//2 + img_w//2 + 5,y-ball_h//2), ballImg)
            
            np.copyto(scratchNP[0],img_to_array(scratchImg))            
            predictions = cnn_model.predict(scratchNP)
            
            pred_left = predictions[0][0]                            
            pred_right = predictions[0][1]
                        
            #heatmapPix[x,y] = (  int(basePix[x,y][0] * 0.4 + pred_left*153.0), int(basePix[x,y][1] * 0.4 + pred_right*153.0), 0)
            heatmapPix[x,y] = (int(pred_left*255.0), int(pred_right*255.0), 0)
    
    print('done')
    heatmapImg = heatmapImg.resize( (heatmapImg.size[0]*6,heatmapImg.size[1]*6), Image.ANTIALIAS)
    
    # overlay the run number on the image
    r = int(runNumber)
    x = heatmapImg.size[0]
    while r >= 0:
        n = r % 10
        r = r // 10
        
        numImg = Image.open('resources/num{}.png'.format(n), 'r')
        
        x -= numImg.size[0]
        heatmapImg.paste(numImg, (x,heatmapImg.size[1]-numImg.size[1]),numImg)
        heatmapImg.paste(numImg, (x,heatmapImg.size[1]-numImg.size[1]),numImg)
        heatmapImg.paste(numImg, (x,heatmapImg.size[1]-numImg.size[1]),numImg)
        
        if r == 0:
            break
    
    heatmapImg.save(outputPath)
    
    

#maxTrainingRun = train.ConfirmTrainingNumber()
#for i in range(0,maxTrainingRun-1):
#    ExportHeatmapForModel(i, 'heatmap_{}.png'.format(i))



