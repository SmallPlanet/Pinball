import onionGpio
import time
import socket
import sys
from thread import *

HOST = ''   # Symbolic name, meaning all available interfaces
PORT = 8000 # Arbitrary non-privileged port

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
print 'Socket created'

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
    #Sending message to connected client
    conn.send('Welcome to the server. Type something and hit enter\n') #send only takes string

    #infinite loop so that function do not terminate and thread do not end.
    while True:

        #Receiving from client
        data = conn.recv(1024)
        reply = 'OK...' + data
        if not data:
            break

	gpioObject.setValue(1)
        time.sleep(0.2)
        gpioObject.setValue(0)

        conn.sendall(reply)

    #came out of loop
    conn.close()


gpioObject  = onionGpio.OnionGpio(11)

status = gpioObject.setOutputDirection(0)

value = 0
while True:
    conn, addr = s.accept()
    print 'Connected with ' + addr[0] + ':' + str(addr[1])
    start_new_thread(clientthread, (conn,))
#    value = (value + 1) % 2
#    status = gpioObject.setValue(value)
#    time.sleep(1)

s.close()

