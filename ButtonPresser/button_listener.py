import onionGpio
import time
import socket
import sys
from thread import *
from OmegaExpansion import relayExp

# relays

relayBank1 = 6  # Left flippers
relayBank2 = 7  # Right flippers

print("Init relay bank 1: ", relayExp.driverInit(relayBank1))
print("Check relay bank 1: ", relayExp.checkInit(relayBank1))

print("Init relay bank 2: ", relayExp.driverInit(relayBank2))
print("Check relay bank 2: ", relayExp.checkInit(relayBank2))


# TCP socket

HOST = ''   # Symbolic name, meaning all available interfaces
PORT = 8000 # Arbitrary non-privileged port

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
print 'Socket created'
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR,1 )

#Bind socket to local host and port
try:
    s.bind((HOST, PORT))
except socket.error as msg:
    print 'Bind failed. Error Code : ' + str(msg[0]) + ' Message ' + msg[1]
    sys.exit()

print 'Socket bind complete'

#Start listening on socket
s.listen(10)
print 'Socket now listening'

#Function for handling connections. This will be used to create threads
def clientthread(conn):
    #infinite loop so that function do not terminate and thread do not end.
    while True:

        #Receiving from client
        data = conn.recv(1024)

        if not data:
	    reply = chr(1) # 1 = FAILURE
            break

        value = 1
        if data.endswith("0"):
            value = 0

        if data.startswith("R"):
            relayExp.setChannel(relayBank2, 1, value)
            relayExp.setChannel(relayBank2, 0, value)
        else:
            relayExp.setChannel(relayBank1, 0, value)

        reply = chr(0) # 0 == OKAY
        conn.sendall(reply)

    #came out of loop
    conn.close()


value = 0
while True:
    conn, addr = s.accept()
    print 'Connected with ' + addr[0] + ':' + str(addr[1])
    start_new_thread(clientthread, (conn,))

s.close()
