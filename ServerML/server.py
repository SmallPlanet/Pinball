import multicast
import time
import train
import uuid
import random

shortTermMemoryDuration = 3
longTermMemoryMaxSize = 100

currentPlayer = 0
scoreByPlayer = [0,0,0,0,0]

shortTermMemory = []

class Memory:
        
    def __init__(self, jpeg, left, right, start, ballKicker):
        self.startEpoc = time.time()
        self.startScore = scoreByPlayer[currentPlayer]
        self.jpeg = jpeg
        self.left = left
        self.right = right
        self.start = start
        self.ballKicker = ballKicker
    
    def CommitMemory(self):
        
        actualScore = scoreByPlayer[currentPlayer] - self.startScore
        
        # TODO: make this smarter, we want to remember the top X high scoring memories?
        if actualScore > 0:
            print("  -> long term memory:", len(self.jpeg), self.left, self.right, self.start, self.ballKicker)
            
            savePath = '%s/%d_%d_%d_%d_%d_%s.jpg' % (train.train_path, actualScore, self.left, self.right, self.start, self.ballKicker, str(uuid.uuid4()))
            print (savePath)
        
            f = open(savePath, 'wb')
            f.write(x.jpeg)
            f.close()

def ResetGame():
    currentPlayer = 0
    scoreByPlayer = [0,0,0,0,0]

def SimulateGameplay():
    if random.random() < 0.001:
        
        # randomly increase our score
        scoreByPlayer[currentPlayer] += random.random() * 100
        print("  Simulated scores: ", scoreByPlayer)
        
        # randomly lose our ball...


print("Begin server main loop...")
while True:
    
    didProcessMessage = False
    
    # messages from OCR app
    key,value = multicast.UpdateListenForGameUpdates()
    if key is not None:
        didProcessMessage = True
        if key == 's':
            scoreByPlayer[currentPlayer] = int(value)
            print("  Received scores: ", scoreByPlayer)
    
        if key == 'x':
            print("  Received game over")
    
        if key == 'b':
            print("  Received begin new game")
        
    
    # messages from ML app
    jpeg,left,right,start,ballKicker = multicast.UpdateListenForGameImages()
    if jpeg is not None:
        didProcessMessage = True
        
        # save this in memory for x number of seconds, after which tag it with how much the
        # score changed and then save it to long term memory if it good enough to do so
        print("  -> short term memory:", len(jpeg), left, right, start, ballKicker)
        shortTermMemory.append(Memory(jpeg, left, right, start, ballKicker))
    
    
    # run through short term memory and see if we should save it to
    # long term memory
    currentEpoc = time.time()
    
    for i in xrange(len(shortTermMemory) - 1, -1, -1):
        x = shortTermMemory[i]
        if x.startEpoc + shortTermMemoryDuration < currentEpoc:
            x.CommitMemory()
            del shortTermMemory[i]
    
    
    # TODO: When current player changes, or when current player ball changes, we should
    # manually complete all short term memories
    
    
    if didProcessMessage == False:
        time.sleep(0.001)
    
    
    # NOTE: Gameplay simulator, useful for self-testing when not near the pinball machine
    #SimulateGameplay()



    