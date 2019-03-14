# Description

Streaming and control of NEURON simulations using OpenFrameworks 

# Usage

See python scripts `test_*.py`.

# Installation

- Set up a working NEURON installation

- Make sure libzmq libraries are on your library path

    + use the ones distributed through your operating system's package manager or get them yourself (see [libzmq GitHub page](https://github.com/zeromq/libzmq))

- Compile NMODL mechanisms with static linking to zmq library:

```sh
# -l:mylib.a instructs static linking
nrnivmodl -incflags -llibzmq -loadflags -l:libzmq.a
```