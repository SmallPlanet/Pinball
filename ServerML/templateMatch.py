import cv2
import numpy as np
from PIL import Image

ballTemplate = cv2.imread('match_ball.png')

# code to score an image with a blurriness factor
def ContainsAtLeatOneBall(jpg, cutoff=0.75):
    image = cv2.imdecode(jpg, -1)    
    # method: TM_SQDIFF, TM_SQDIFF_NORMED, TM_CCORR, TM_CCORR_NORMED, TM_CCOEFF, TM_CCOEFF_NORMED
    result = cv2.matchTemplate(image, ballTemplate, cv2.TM_CCOEFF_NORMED)
    loc = np.where(result >= cutoff)
    return len(loc[0]) > 0