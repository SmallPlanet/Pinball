import zmq


# Endpoint port numbers work like this:
# - the endpoint url has everything but the last digit of the port number
# - if you are a subscriber, concatenate 1 to the string 
# - if you are a publisher, concatenate 2 to the string 
#
# Example: the base port number for GameInfo updates is 60000; subscribers connec to 60001 and publishers connect to 60002

serverName = "ServerML"

endpoint_GameInfo = "tcp://*:6000"
endpoint_pub_GameInfo = endpoint_GameInfo.replace("*", serverName)+"2"
endpoint_sub_GameInfo = endpoint_GameInfo.replace("*", serverName)+"1"

endpoint_TrainingImages = "tcp://*:6001"
endpoint_pub_TrainingImages = endpoint_TrainingImages.replace("*", serverName)+"2"
endpoint_sub_TrainingImages = endpoint_TrainingImages.replace("*", serverName)+"1"

endpoint_RemoteControl = "tcp://*:6002"
endpoint_pub_RemoteControl = endpoint_RemoteControl.replace("*", serverName)+"2"
endpoint_sub_RemoteControl = endpoint_RemoteControl.replace("*", serverName)+"1"





context = zmq.Context()
poller = zmq.Poller()
socket2callback = {}


def publisher(endpoint):
    socket = context.socket(zmq.PUB)
    socket.bind(endpoint)
    return socket

def subscriber(endpoint, func):
    socket = context.socket(zmq.SUB)
    print("connecting to: " + endpoint)
    socket.connect(endpoint)
    socket.setsockopt(zmq.SUBSCRIBE, "")
    poller.register(socket, zmq.POLLIN)
    socket2callback[socket] = func
    return socket

def PollSockets():
    didProcessMessage = False
    socks = dict(poller.poll())
    for socket in socks:
        if socks[socket] == zmq.POLLIN:
            msg = socket.recv()
            socket2callback[socket](msg)
            didProcessMessage = True
    return didProcessMessage
    