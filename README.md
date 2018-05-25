Tried commands:

```sh
# Error when import neuron and loading libnrnmech.so
nrnivmodl -incflags -I/usr/include/zmq.h -loadflags /usr/lib/x86_64-linux-gnu/libzmq.so

# Error when importing neuron and loading libnrnmech.so
nrnivmodl -incflags -llibzmq -loadflags -L/usr/lib/x86_64-linux-gnu

# WORKS (-l:mylib.a instructs static linking)
nrnivmodl -incflags -llibzmq -loadflags -l:libzmq.a
```