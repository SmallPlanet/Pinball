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
import numpy as np
import blur
import templateMatch

# how far reaching into the past scores earned should affect the reward value associated with
# actions.  1 means its stretches far, 0 means its very near sighted
shortTermLearningRate = 0.94

# the absolaute maximum number of seconds a memory can be affected by new scores; when a short
# term memory exceeeds this threashold is it converted to a long term memory
# NOTE: all memories are committed immediately when the active player changes
shortTermMemoryDuration = 30

# absoluate maximum number of long term memories to store on disk; when the threashold is
# reached memories with least reward are thrown away
longTermMemoryMaxSize = 50000

# if an action does not score more than this it will not be considered for long term memory storage
longTermMemoryMinimumReward = 0

# when a player loses a ball, that should negatively impact actions taken before the lost ball
penaltyForLostBall = -4000000

class ScoreEvent:
    def __init__(self, player, differentialScore):
        self.scoreEpoc = time.time()
        self.player = player
        self.differentialScore = differentialScore
        
        print("  new scoring event", self.scoreEpoc, self.player, self.differentialScore)
        
    
    def rewardForMemory(self, memory):
        # if this score happened before the action, it should not affect it
        if self.scoreEpoc < memory.startEpoc:
            return 0
        
        # number of seconds after the event the change in score happend
        t = self.scoreEpoc - memory.startEpoc
        
        # basic idea is we want the affect of the score to fall off over time
        # note: i'm sure there is a more fantastic method for doing this, but for now
        # it means scores will falloff over quarter second intervals, fall off less
        # the closer shortTermLearningRate is to 1
        reward = self.differentialScore
        x = int(t * 4)
        while x > 0:
            reward *= shortTermLearningRate
            x -= 1
            
        #print("  calculated", t, int(t * 4), reward, self.differentialScore)
        
        return reward
        
        

class GameStateInfo:
    currentPlayer = 0
    scoreByPlayer = [-1,-1,-1,-1]
    scoringEvents = []
    
    def Reset(self):
        currentPlayer = 0
        scoreByPlayer = [-1,-1,-1,-1]
        scoringEvents = []


gameState = GameStateInfo()

shortTermMemory = []
longTermMemory = []

class Memory:
    
    def __repr__(self):
        return '%d:%d,%d,%d' % (self.reward, self.left, self.right, self.ballKicker)
        
    def __init__(self, filePath=None, jpeg=None, diffScore=0, left=None, right=None, ballKicker=None):
        self.startEpoc = time.time()
        self.reward = 0
        self.jpeg = jpeg
        self.left = left
        self.right = right
        self.ballKicker = ballKicker
        self.filePath = filePath
    
    
    def CommitMemory(self, pointScale):
        
        # run through all scoring events for this player, add up their reward for this action
        self.reward = 0
        
        for scoreEvent in gameState.scoringEvents:
            if scoreEvent.player == gameState.currentPlayer:
                self.reward += scoreEvent.rewardForMemory(self)
        
        # we want to reward clean shots, not just randomly flipping the flippers a thousand times a second
        self.reward *= pointScale
                
        #print("commit reward", self.reward)
                
        # sort the long term memory such that the lowest diff score memory is first
        longTermMemory.sort(reverse=False, key=GetMemoryKey)
        
        jpegAsBinary = np.frombuffer(self.jpeg, dtype='b')
        
        # blurry images we should send to waste
        isBlurry = blur.IsBlurryJPEG(jpegAsBinary, cutoff=3000)
        
        # images should always contain at least one ball (note: this is not the most accurate method for ball detection, but hopefully it is better than nothing)
        hasBall = templateMatch.ContainsAtLeatOneBall(jpegAsBinary, 0.80)
        
        if isBlurry == False:
            # Check to see if our differential score is better than the worst differential scored memory; if so, save it to disk
            if self.reward > longTermMemoryMinimumReward:
                print("  -> long term memory:", self.reward, self.left, self.right, self.ballKicker)
            
                longTermMemory.append(self)
                longTermMemory.sort(reverse=False, key=GetMemoryKey)
            
                self.filePath = '%s/%d_%d_%d_%d_%s.jpg' % (train.TrainingMemoryPath() if hasBall == True else train.TempMemoryPath(), self.reward, self.left, self.right, self.ballKicker, str(uuid.uuid4()))
                print (self.filePath)
        
                f = open(self.filePath, 'wb')
                f.write(self.jpeg)
                f.close()
            elif self.reward < 0:
                # If this shot somehow contributed to losing the ball, we want to put it into waste
                # If the image captured was blurry, we should also put it into waste
                print("  -> waste bin:", self.reward, self.left, self.right, self.ballKicker)
            
                self.filePath = '%s/%d_%d_%d_%d_%s.jpg' % (train.WasteMemoryPath() if hasBall == True else train.TempMemoryPath(), self.reward, 0, 0, 0, str(uuid.uuid4()))
                print (self.filePath)
        
                f = open(self.filePath, 'wb')
                f.write(self.jpeg)
                f.close()
            
            
        
        # Now we need to ensure our long term memory does not exceed our established maximum, so forget
        # the least valuable memories until we are under the maximum
        while len(longTermMemory) > longTermMemoryMaxSize:
            memory = longTermMemory[0]
            os.remove(memory.filePath)
            longTermMemory.remove(memory)
        

def GetMemoryKey(item):
    return item.reward

def LoadLongTermMemory():
    all_img_paths = glob.glob(os.path.join(train.TrainingMemoryPath(), '*.jpg'))
    
    for img_path in all_img_paths:
        labels = images.get_labels_and_score(img_path)
        
        longTermMemory.append(Memory(img_path, None, labels[0], labels[1], labels[2], labels[3]))
    
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
    
    if random.random() < 0.01:
        player = gameState.currentPlayer
        if player == 0:
            player = 1
        else:
            player = 0
        newScore = gameState.scoreByPlayer[player] + random.random() * 100
        HandleGameInfo('m:{0},{1}'.format(player+1, int(newScore)))
    
    if random.random() < 0.05:
        newScore = gameState.scoreByPlayer[gameState.currentPlayer] + random.random() * 100
        HandleGameInfo('m:{0},{1}'.format(gameState.currentPlayer+1, int(newScore)))
    

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


def HandleChangeInScore(player, newScore):
    differentialScore = newScore - gameState.scoreByPlayer[player]
    if differentialScore < 0:
        differentialScore = 0
    gameState.scoreByPlayer[player] = newScore
    
    gameState.scoringEvents.append(ScoreEvent(player, differentialScore))
    
    

# messages from OCR app
def HandleGameInfo(msg):   
    print(msg) 
    parts = msg.split(":")
    if len(parts) == 2:
        # single player score
        if parts[0] == 's':
            HandleChangeInScore(gameState.currentPlayer, int(parts[1]))
            
        # multiplayer scoring, includes current player as the first item and score as second item
        if parts[0] == 'm':
            parts2 = parts[1].split(",")
            newPlayer = int(parts2[0])-1
            if newPlayer != gameState.currentPlayer:
                HandlePlayerLostBall()
                gameState.currentPlayer = newPlayer
            
            HandleChangeInScore(gameState.currentPlayer, int(parts2[1]))
        
        # ball count, includes current player as the first item and ball number as the second item
        # note: we only receive this once when the ball number changes per player, so we can
        # simply act on it
        if parts[0] == 'b':
            parts2 = parts[1].split(",")
            ballPlayer = int(parts2[0])-1
            if ballPlayer == gameState.currentPlayer:
                HandlePlayerLostBall()
            
        # start of new player turn
        if parts[0] == 'p':
            HandlePlayerLostBall()
            gameState.currentPlayer = int(parts[1])-1
            print("  Player " + parts[1] + " is up!")
            
        # game over
        if parts[0] == 'x':
            HandlePlayerLostBall()
            gameState.Reset()
            print("  Received game over")
        
        # push start
        if parts[0] == 'g':
            gameState.Reset()
            print("  Received begin new game")

comm.subscriber(comm.endpoint_sub_GameInfo, HandleGameInfo)


def HandlePlayerLostBall():
    print("  *** HANDLE LOST BALL ***")
    gameState.scoringEvents.append(ScoreEvent(gameState.currentPlayer, penaltyForLostBall))
    CommitMemoryArray(shortTermMemory)
    


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
        filePath = '%s/%d_%d_%d_%d_%s.jpg' % (train.PermanentMemoryPath(), 999, left, right, ballKicker, str(uuid.uuid4()))
        print (filePath)
    
        f = open(filePath, 'wb')
        f.write(jpeg)
        f.close()
        
    else:
        # save this in memory for x number of seconds, after which tag it with how much the
        # score changed and then save it to long term memory if it good enough to do so
        print("  -> short term memory:", len(jpeg), left, right, ballKicker)
        shortTermMemory.append(Memory(None, jpeg, 0, left, right, ballKicker))
    
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
    
    #2) for all of the elapsed memories, commit them
    CommitMemoryArray(elapsedShortTermMemories)
    
    
    # TODO: When current player changes, or when current player ball changes, we should
    # manually complete all short term memories
    
    if didProcessMessage == False:
        time.sleep(0.001)
    
    
    # NOTE: Gameplay simulator, useful for self-testing when not near the pinball machine
    #SimulateGameplay()



    