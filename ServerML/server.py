import multicast
import time

currentPlayer = 0
scoreByPlayer = [0,0,0,0,0]

def ResetGame():
    currentPlayer = 0
    scoreByPlayer = [0,0,0,0,0]


while True:
    
    didProcessMessage = False
    
    # messages from OCR app
    key,value = multicast.UpdateListenForGameUpdates()
    if key is not None:
        didProcessMessage = True
        if key == 's':
            scoreByPlayer[currentPlayer] = int(value)
            print("scores: ", scoreByPlayer)
    
        if key == 'x':
            print("game over")
    
        if key == 'b':
            print("begin new game")
        
    
    # messages from ML app
    jpeg,left,right,start,ballKicker = multicast.UpdateListenForGameImages()
    if jpeg is not None:
        didProcessMessage = True
        
        print("image", len(jpeg), left, right, start, ballKicker)
        
        f = open('./output.jpg', 'wb')
        f.write(jpeg)
        f.close()
    
    
    if didProcessMessage == False:
        time.sleep(0.001)

    