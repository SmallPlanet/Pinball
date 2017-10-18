import comm
import time
import train
import uuid
import random
import forwarder
import images
import struct
import os
import glob

shortTermMemoryDuration = 3
longTermMemoryMaxSize = 100

class GameStateInfo:
    currentPlayer = 0
    scoreByPlayer = [-1,-1,-1,-1]
    
    def Reset(self):
        currentPlayer = 0
        scoreByPlayer = [-1,-1,-1,-1]


gameState = GameStateInfo()

shortTermMemory = []
longTermMemory = []

class Memory:
    
    def __repr__(self):
        return '%d:%d,%d,%d,%d' % (self.differentialScore, self.left, self.right, self.start, self.ballKicker)
        
    def __init__(self, filePath=None, jpeg=None, diffScore=0, left=None, right=None, start=None, ballKicker=None):
        self.startEpoc = time.time()
        self.startScore = gameState.scoreByPlayer[gameState.currentPlayer]
        self.differentialScore = diffScore
        self.jpeg = jpeg
        self.left = left
        self.right = right
        self.start = start
        self.ballKicker = ballKicker
        self.filePath = filePath
    
    
    def CommitMemory(self):
        
        self.differentialScore = gameState.scoreByPlayer[gameState.currentPlayer] - self.startScore
        
        # sort the long term memory such that the lowest diff score memory is first
        longTermMemory.sort(reverse=False, key=getMemoryKey)
        
        # Check to see if our differential score is better than the worst differential scored memory; if so, save it to disk
        if self.differentialScore > longTermMemory[0].differentialScore:
            print("  -> long term memory:", len(self.jpeg), self.left, self.right, self.start, self.ballKicker)
            
            longTermMemory.append(self)
            longTermMemory.sort(reverse=False, key=getMemoryKey)
            
            self.filePath = '%s/%d_%d_%d_%d_%d_%s.jpg' % (train.train_path, self.differentialScore, self.left, self.right, self.start, self.ballKicker, str(uuid.uuid4()))
            print (self.filePath)
        
            f = open(self.filePath, 'wb')
            f.write(x.jpeg)
            f.close()
        
        # Now we need to ensure our long term memory does not exceed our established maximum
        while len(longTermMemory) > longTermMemoryMaxSize:
            memory = longTermMemory[0]
            os.remove(memory.filePath)
            longTermMemory.remove(memory)
        

def getMemoryKey(item):
    return item.differentialScore

def LoadLongTermMemory():
    all_img_paths = glob.glob(os.path.join(train.train_path, '*.jpg'))
    
    for img_path in all_img_paths:
        labels = images.get_labels_and_score(img_path)
        
        longTermMemory.append(Memory(img_path, None, labels[0], labels[1], labels[2], labels[3], labels[4]))
    
    longTermMemory.sort(reverse=True, key=getMemoryKey)
    print("loaded " + str(len(longTermMemory)) + " memories from disk")
    print(longTermMemory)
        
LoadLongTermMemory()

def SimulateGameplay():
    if random.random() < 0.01:
        
        # randomly increase our score
        gameState.scoreByPlayer[gameState.currentPlayer] += random.random() * 100
        print("  Simulated scores: ", gameState.scoreByPlayer)



# messages from OCR app
def HandleGameInfo(msg):   
    #print(msg) 
    parts = msg.split(":")
    if len(parts) == 2:
        if parts[0] == 's':
            gameState.scoreByPlayer[gameState.currentPlayer] = int(parts[1])
            print("  Received scores: ", gameState.scoreByPlayer)
        if parts[0] == 'm':
            parts2 = parts[1].split(",")
            gameState.currentPlayer = int(parts2[0])-1
            gameState.scoreByPlayer[gameState.currentPlayer] = int(parts2[1])
            print("  Received scores: ", gameState.scoreByPlayer)
        if parts[0] == 'p':
            gameState.currentPlayer = int(parts[1])-1
            print("  Player " + parts[1] + " is up!")
        if parts[0] == 'x':
            gameState.Reset()
            print("  Received game over")
        if parts[0] == 'b':
            gameState.Reset()
            print("  Received begin new game")

comm.subscriber(comm.endpoint_sub_GameInfo, HandleGameInfo)


# messages from ML app
def HandleTrainingImages(msg):
    # format is:
    # 32 bit int for size of jpeg data
    # ^^ amount of jpeg data bytes
    # byte for left button is activated
    # byte for right button is activated
    # byte for start button is activated
    # byte for ball kicker button is activated
    sizeOfJPEG = struct.unpack("<L", msg[:4])[0]
    jpeg = msg[4:4+sizeOfJPEG]
    
    s = 4+sizeOfJPEG
    
    left = struct.unpack("B", msg[s+0:s+1])[0]
    right = struct.unpack("B", msg[s+1:s+2])[0]
    start = struct.unpack("B", msg[s+2:s+3])[0]
    ballKicker = struct.unpack("B", msg[s+3:s+4])[0]
    
    # save this in memory for x number of seconds, after which tag it with how much the
    # score changed and then save it to long term memory if it good enough to do so
    print("  -> short term memory:", len(jpeg), left, right, start, ballKicker)
    shortTermMemory.append(Memory(None, jpeg, 0, left, right, start, ballKicker))
    
comm.subscriber(comm.endpoint_sub_TrainingImages, HandleTrainingImages)


print("Begin server main loop...")
while True:
    
    didProcessMessage = comm.PollSockets()
    
    # run through short term memory and see if we should save it to
    # long term memory
    currentEpoc = time.time()
    
    # 1) gather all of the elapsed memories into one array
    for i in xrange(len(shortTermMemory) - 1, -1, -1):
        x = shortTermMemory[i]
        if x.startEpoc + shortTermMemoryDuration < currentEpoc:
            x.CommitMemory()
            del shortTermMemory[i]
    
    #2) for all of the elapsed memories, commit them with the evenly distributed score gains
    
    
    
    # TODO: When current player changes, or when current player ball changes, we should
    # manually complete all short term memories
    
    if didProcessMessage == False:
        time.sleep(0.001)
    
    
    # NOTE: Gameplay simulator, useful for self-testing when not near the pinball machine
    #SimulateGameplay()



    