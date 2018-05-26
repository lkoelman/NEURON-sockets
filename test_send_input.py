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
double_array2 = ctypes.c_double * 2

# Launch flurry of data
try:
    # Construct message in agreed format
    group_id = 1.0
    # raw_data = double_array2(group_id, weight_value)
    # byte_data = bytearray(raw_data) # good for printing

    weight_value = 0.0
    while True:
        weight_value = (weight_value + 1) % 100
        raw_data = double_array2(group_id, weight_value)

        sleep(10e-3) # wait for 10 ms between packets
        print("Sending data {} ...".format(raw_data))
        socket.send(raw_data)

except KeyboardInterrupt:
    socket.close()
    sys.exit()