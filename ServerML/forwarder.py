import zmq
import comm
from  multiprocessing import Process



# This is a message forwarder, a basic proxy service so publishers and subscribers can be dynamic without a well
# known address.  Note that the normal rules for pub/sub port assigned listed above are reversed
# for the proxey service
def forwarder(endpoint):
    try:
        context = zmq.Context()
        
        # Subscribers
        subscribers = context.socket(zmq.SUB)        
        subscribers.bind(endpoint+"2")
        subscribers.setsockopt(zmq.SUBSCRIBE, "")
        
        # Publishers
        publishers = context.socket(zmq.PUB)        
        publishers.bind(endpoint+"1")        
        
        print "forwarder: " + endpoint+"1" + " -> " + endpoint+"2"
        
        zmq.device(zmq.FORWARDER, subscribers, publishers)
    except Exception, e:
        print e
        print "forwarder closing..."
    finally:
        pass
        if subscribers != None:
            subscribers.close()
        if publishers != None:
            publishers.close()
        context.term()



# Spawna process to handle the forwarder
Process(target=forwarder, args=(comm.endpoint_GameInfo,)).start()
Process(target=forwarder, args=(comm.endpoint_TrainingImages,)).start()
Process(target=forwarder, args=(comm.endpoint_RemoteControl,)).start()
Process(target=forwarder, args=(comm.endpoint_CoreMLUpdates,)).start()

