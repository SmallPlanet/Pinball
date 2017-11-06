from __future__ import division
from keras.callbacks import *

class WeightedLR(Callback):
    # this learning rate schedular will adjust the learning rate based upon a factor
    # known in the training material

    def __init__(self, image_weights, base_lr=0.001, max_lr=0.006):
        super(WeightedLR, self).__init__()
        self.image_weights = image_weights
        self.image_idx = 0
        self.base_lr = base_lr
        self.max_lr = max_lr
        self.max_weight = max(image_weights)
        
                
    def on_epoch_begin(self, epoch, logs):
        # at the start of each epoch, reset our weight index
        self.image_idx = 0
        
    def on_batch_begin(self, batch, logs):
        # logs.batch = the index of this batch
        # logs.size = the number of training samples in this batch
                
        # for this batch, run over the next logs.size image wieghts and average them
        # use this weight to inform the learning rate for this batch
        log_size = logs.get("size")
        
        avg = 0
        for x in range(self.image_idx, self.image_idx + log_size):
            avg += self.image_weights[x]
        
        avg /= log_size
        
        normalized_weight = avg / self.max_weight
        
        weighted_lr = self.base_lr + (self.max_lr - self.base_lr) * normalized_weight
        
        # now we have the average of all weights in this batch, normalize them to
        # put them in a reasonable range for learning rate
        K.set_value(self.model.optimizer.lr,  weighted_lr)
        
        # advance our image_idx for next time
        self.image_idx += log_size
        
        
        
            
            

  
