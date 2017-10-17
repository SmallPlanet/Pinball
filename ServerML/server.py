import comm
import time
import train
import uuid
import random
import forwarder
import struct


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
    if random.random() < 0.01:
        
        # randomly increase our score
        scoreByPlayer[currentPlayer] += random.random() * 100
        print("  Simulated scores: ", scoreByPlayer)
        
        # randomly lose our ball...




# messages from OCR app
def HandleGameInfo(msg):
    parts = msg.split(":")
    if len(parts) == 2:
        if parts[0] == 's':
            scoreByPlayer[currentPlayer] = int(parts[1])
            print("  Received scores: ", scoreByPlayer)
        if parts[0] == 'x':
            print("  Received game over")
        if parts[0] == 'b':
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
    shortTermMemory.append(Memory(jpeg, left, right, start, ballKicker))
    
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
    SimulateGameplay()



    