from __future__ import division

import comm
import forwarder
import time
import train
import uuid
import random
import images
import struct
import os
import glob

# The goal here is to distribute the points earned fairly to the actions taken. As such,
# we need to assign only the point earned and not amny more. For example, if 5 actions
# were take in quick succession and over the next N seconds that resulted in a score
# increase of 500 pts, then that 500 pts needs to be distrubted somehow across those
# 5 actions, and NOT each action gets 500 pts
#
# This can be accomplished but the scoreDrainByPlayer; each time some points are assigned
# to an action, this value increases by the same so we can calculate the amount of 
# unassigned points there are left to assign

shortTermMemoryDuration = 2
longTermMemoryMaxSize = 50000

class GameStateInfo:
    currentPlayer = 0
    scoreByPlayer = [-1,-1,-1,-1]
    scoreDrainByPlayer = [0,0,0,0]
    
    def Reset(self):
        currentPlayer = 0
        scoreByPlayer = [-1,-1,-1,-1]
        scoreDrainByPlayer = [0,0,0,0]


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
    
    
    def CommitMemory(self, pointScale):
        
        # calculate the total number of points scored during this memory's unique time frame
        totalPointsPossible = gameState.scoreByPlayer[gameState.currentPlayer] - self.startScore
        
        print("totalPointsPossible", totalPointsPossible)
        
        # multiply the total points possible by the pointScale, this helps ensure one memory does not
        # hog all of the points
        totalPointsPossible = totalPointsPossible * pointScale
        
        print("totalPointsPossible after scale", totalPointsPossible)
        
        # drain points from the point pool up to totalPointsPossible, without exceeding the pool limits
        self.differentialScore = 0
        while self.differentialScore < totalPointsPossible and gameState.scoreDrainByPlayer[gameState.currentPlayer] < gameState.scoreByPlayer[gameState.currentPlayer]:
            self.differentialScore += 1
            gameState.scoreDrainByPlayer[gameState.currentPlayer] += 1
        
        
        # sort the long term memory such that the lowest diff score memory is first
        longTermMemory.sort(reverse=False, key=GetMemoryKey)
                
        # Check to see if our differential score is better than the worst differential scored memory; if so, save it to disk
        if self.differentialScore > 1:
            print("  -> long term memory:", self.differentialScore, self.left, self.right, self.start, self.ballKicker)
            
            longTermMemory.append(self)
            longTermMemory.sort(reverse=False, key=GetMemoryKey)
            
            self.filePath = '%s/%d_%d_%d_%d_%d_%s.jpg' % (train.train_path, self.differentialScore, self.left, self.right, self.start, self.ballKicker, str(uuid.uuid4()))
            print (self.filePath)
        
            f = open(self.filePath, 'wb')
            f.write(x.jpeg)
            f.close()
        else:
            print("  -> waste bin:", self.differentialScore, self.left, self.right, self.start, self.ballKicker)
            
            self.filePath = '%s/%d_%d_%d_%d_%d_%s.jpg' % (train.waste_path, 0, 0, 0, 0, 0, str(uuid.uuid4()))
            print (self.filePath)
        
            f = open(self.filePath, 'wb')
            f.write(x.jpeg)
            f.close()
            
            
        
        # Now we need to ensure our long term memory does not exceed our established maximum, so forget
        # the least valuable memories until we are under the maximum
        while len(longTermMemory) > longTermMemoryMaxSize:
            memory = longTermMemory[0]
            os.remove(memory.filePath)
            longTermMemory.remove(memory)
        

def GetMemoryKey(item):
    return item.differentialScore

def LoadLongTermMemory():
    all_img_paths = glob.glob(os.path.join(train.train_path, '*.jpg'))
    
    for img_path in all_img_paths:
        labels = images.get_labels_and_score(img_path)
        
        longTermMemory.append(Memory(img_path, None, labels[0], labels[1], labels[2], labels[3], labels[4]))
    
    longTermMemory.sort(reverse=True, key=GetMemoryKey)
    print("loaded " + str(len(longTermMemory)) + " memories from disk")
    print(longTermMemory)
        
LoadLongTermMemory()

def ClearMemoryArray(array):
    n = len(array)
    while len(array) > 0:
        del array[0]

def CommitMemoryArray(array):
    n = len(array)
    while len(array) > 0:
        array[0].CommitMemory(1.0/n)
        del array[0]

def SimulateGameplay():
    if random.random() < 0.05:
        # randomly increase our score
        gameState.scoreByPlayer[gameState.currentPlayer] += random.random() * 100
        print("  Simulated scores: ", gameState.scoreByPlayer)
    
    if random.random() < 0.01:
        # randomly change the player
        CommitMemoryArray(shortTermMemory)
        if gameState.currentPlayer == 0:
            gameState.currentPlayer = 1
        else:
            gameState.currentPlayer = 0
        print("  Player changed: ", gameState.currentPlayer, gameState.scoreByPlayer)


# messages from CoreML updates, adding just for debugging
#def HandleCoreMLUpdate(msg):   
#    print("HandleCoreMLUpdate: ")
#comm.subscriber(comm.endpoint_sub_CoreMLUpdates, HandleCoreMLUpdate)

# messages from Remote control app, adding just for debugging
def HandleRemoteControlInfo(msg):   
    if msg == "train":
        CommitMemoryArray(shortTermMemory)
        train.Learn()
comm.subscriber(comm.endpoint_sub_RemoteControl, HandleRemoteControlInfo)

# messages from OCR app
def HandleGameInfo(msg):   
    print(msg) 
    parts = msg.split(":")
    if len(parts) == 2:
        # single player score
        if parts[0] == 's':
            gameState.scoreByPlayer[gameState.currentPlayer] = int(parts[1])
            print("  Received scores: ", gameState.scoreByPlayer)
            
        # multiplayer scoring, includes current player as the first item and score as second item
        if parts[0] == 'm':
            parts2 = parts[1].split(",")
            newPlayer = int(parts2[0])-1
            if newPlayer != gameState.currentPlayer:
                ClearMemoryArray(shortTermMemory)
                gameState.currentPlayer = newPlayer
                
            gameState.scoreByPlayer[gameState.currentPlayer] = int(parts2[1])
            print("  Received scores: ", gameState.scoreByPlayer)
            
        # start of new player turn
        if parts[0] == 'p':
            ClearMemoryArray(shortTermMemory)
            gameState.currentPlayer = int(parts[1])-1
            print("  Player " + parts[1] + " is up!")
            
        # game over
        if parts[0] == 'x':
            gameState.Reset()
            print("  Received game over")
        
        # push start
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
    
    
    # save all ball kickers and 0-0-0-0 to permanent memory
    if left == 0 and right == 0 and start == 0:
        print("  -> permanent memory:", len(jpeg), left, right, start, ballKicker)
        
        # permanent memories get saved automatically to the permanent memory path
        filePath = '%s/%d_%d_%d_%d_%d_%s.jpg' % (train.permanent_path, 999, left, right, start, ballKicker, str(uuid.uuid4()))
        print (filePath)
    
        f = open(filePath, 'wb')
        f.write(jpeg)
        f.close()
        
    else:
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
    elapsedShortTermMemories = []
    for i in xrange(len(shortTermMemory) - 1, -1, -1):
        x = shortTermMemory[i]
        if x.startEpoc + shortTermMemoryDuration < currentEpoc:
            elapsedShortTermMemories.append(x)
            del shortTermMemory[i]
    
    #2) for all of the elapsed memories, commit them with the evenly distributed score gains
    CommitMemoryArray(elapsedShortTermMemories)
    
    
    # TODO: When current player changes, or when current player ball changes, we should
    # manually complete all short term memories
    
    if didProcessMessage == False:
        time.sleep(0.001)
    
    
    # NOTE: Gameplay simulator, useful for self-testing when not near the pinball machine
    #SimulateGameplay()



    