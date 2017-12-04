import cv2
from PIL import Image

# code to score an image with a blurriness factor
def IsBlurryJPEG(jpg, cutoff=3000):
        
    image = cv2.imdecode(jpg, -1)
        
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    variance = cv2.Laplacian(gray, cv2.CV_64F).var()
    #print("blurry", variance)
    
    return variance < cutoff