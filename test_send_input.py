import zmq
import sys
import ctypes
from time import sleep

context = zmq.Context()

#  Socket to talk to server
print("Connecting to hello world server...")
socket = context.socket(zmq.PUB)
socket.bind("tcp://*:5559")

# C Array constructor
int_array2 = ctypes.c_int * 2

# Launch flurry of data
try:
    while True:
        data = int_array2(1,2)
        # data = bytearray([1,2])

        sleep(10e-3) # wait for 10 ms between packets
        print("Sending data {} ...".format(data))
        socket.send(data)

except KeyboardInterrupt:
    socket.close()
    sys.exit()