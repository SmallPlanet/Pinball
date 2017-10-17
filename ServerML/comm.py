import io

import socket
import struct
import sys
import fcntl, os
import errno
from multiprocessing import Process
import zmq
import time


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
    socks = dict(poller.poll())
    for socket in socks:
        if socks[socket] == zmq.POLLIN:
            msg = socket.recv()
            socket2callback[socket](msg)
    


'''





def connectToMulticastUDP(multicast_group, port):
    server_address = ('', port)
    
    # Create the socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    # Bind to the server address
    sock.bind(server_address)
    
    # Tell the operating system to add the socket to the multicast group
    # on all interfaces.
    group = socket.inet_aton(multicast_group)
    mreq = struct.pack('4sL', group, socket.INADDR_ANY)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    
    # let's attempt to read from this socket in a non-blocking manner...
    sock.setblocking(0)
    
    return sock




# SOCKET CODE TO LISTEN TO OCR APP
# current score
# game over
# push start
# current player
# number of balls left

gameUpdatesSocket = connectToMulticastUDP('239.1.1.234', 35687)

def UpdateListenForGameUpdates():
    
    try:
        msg = gameUpdatesSocket.recv(4096)
    except socket.error, e:
        # Something else happened, handle error, exit, etc.
        # Could also be as simple as "there's no data to read because we're non-blocking"
        
        # 'Resource temporarily unavailable'
        if e.args[0] == 11:
            return (None, None)
        
        print("error: ", e)
        sys.exit(1)
    else:
        parts = msg.split(":")
        
        if len(parts) == 2:
            return (parts[0], parts[1])
    return (None, None)


# SOCKET CODE TO LISTEN TO ML APP
# images of the play field when buttons get activated

imageUpdatesSocket = connectToMulticastUDP('239.1.1.234', 45687)

def UpdateListenForGameImages():
    
    try:
        msg = imageUpdatesSocket.recv(65536)
    except socket.error, e:
        # Something else happened, handle error, exit, etc.
        # Could also be as simple as "there's no data to read because we're non-blocking"
        
        # 'Resource temporarily unavailable'
        if e.args[0] == 11:
            return (None, None, None, None, None)
        
        print("error: ", e)
        sys.exit(1)
    else:        
        # format is:
        # 32 bit int for size of jpeg data
        # ^^ amount of jpeg data bytes
        # byte for left button is activated
        # byte for right button is activated
        # byte for start button is activated
        # byte for ball kicker button is activated
        sizeOfJPEG = struct.unpack("<L", msg[:4])[0]
        jpegBytes = msg[4:4+sizeOfJPEG]
        
        s = 4+sizeOfJPEG
        
        left = struct.unpack("B", msg[s+0:s+1])[0]
        right = struct.unpack("B", msg[s+1:s+2])[0]
        start = struct.unpack("B", msg[s+2:s+3])[0]
        ballKicker = struct.unpack("B", msg[s+3:s+4])[0]
        
        return (jpegBytes, left, right, start, ballKicker)
        
    return (None, None, None, None, None)

'''