import socket
import struct
import sys
import fcntl, os
import errno


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
# images of the play field when buttons are activated