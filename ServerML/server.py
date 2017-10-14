import multicast
import time

currentPlayer = 0
scoreByPlayer = [0,0,0,0,0]

def ResetGame():
    currentPlayer = 0
    scoreByPlayer = [0,0,0,0,0]


while True:
    time.sleep(0.1)
    
    # messages from OCR app
    key,value = multicast.UpdateListenForGameUpdates()
    if key is not None:
        if key == 's':
            scoreByPlayer[currentPlayer] = int(value)
            print("scores: ", scoreByPlayer)
    
        if key == 'x':
            print("game over")
    
        if key == 'b':
            print("begin new game")
    
    # messages from ML app
    

    