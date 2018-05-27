"""
Test script for ZmqOutputEvents.mod.
"""

from neuron import h

h.load_file("stdlib.hoc") # Load the standard library
h.load_file("stdrun.hoc") # Load the standard run library

observer = h.ZmqOutputEvents()
observer.port_number = 5559
observer.use_icp = 0

stims = []
netcons = []
num_stims = 5
for i in range(num_stims):
    stim = h.NetStim()
    stims.append(stim)

    stim.number = 1e9
    stim.start = 5
    stim.noise = 1
    stim.interval = 10 + i
    
    nc = h.NetCon(stim, observer)
    netcons.append(nc)


h.finitialize()
h.tstop = 100
h.run()

# For near-infinite loop:
# h.continuerun(1e12)