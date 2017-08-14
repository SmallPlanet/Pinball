import onionGpio
import time
import socket
import sys
from thread import *
from OmegaExpansion import relayExp

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
            relayExp.setChannel(flipperRelays, 1, value)
            # rightButton.setValue(value)
        else:
            relayExp.setChannel(flipperRelays, 0, value)
            # leftButton..setValue(value)

        reply = chr(0) # 0 == OKAY
        conn.sendall(reply)

    #came out of loop
    conn.close()


leftButton  = onionGpio.OnionGpio(1)
rightButton = onionGpio.OnionGpio(0)
status = leftButton.setOutputDirection(0)
status = rightButton.setOutputDirection(0)

# relays

flipperRelays = 7
relayExp.driverInit(flipperRelays)


value = 0
while True:
    conn, addr = s.accept()
    print 'Connected with ' + addr[0] + ':' + str(addr[1])
    start_new_thread(clientthread, (conn,))

s.close()
