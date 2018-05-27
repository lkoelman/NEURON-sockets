"""
Test script for ZmqOutputEvents.mod.
"""

from neuron import h
import numpy as np

h.load_file("stdlib.hoc") # Load the standard library
h.load_file("stdrun.hoc") # Load the standard run library

observer = h.ZmqOutputVars()
observer.port_number = 5557
observer.use_icp = 0

cell = h.Section()
cell.insert('hh')
cell.insert('pas')

stim = h.IClamp(cell(0.5))
stim.dur = 1e9
stim.delay = 5
stim.amp = 0.1

h.setpointer(cell(0.5)._ref_v, 'temp_ref', observer)
observer.add_ref_to_group(1, 888.0)

# cells = []
# stims = []
# nstims = []
# num_cells = 20
# for i in range(num_cells):
#     cell = h.Section()
#     cells.append(cell)
#     cell.insert('hh')
#     cell.insert('pas')

#     stim = h.IClamp(cell(0.5))
#     stims.append(stim)
#     stim.dur = 1e9
#     stim.delay = 5
#     stim.amp = 0.1

#     stim = h.NetStim()
#     nstims.append(stim)
#     stim.number = 1e9
#     stim.start = 5
#     stim.noise = 1
#     stim.interval = 10

#     # Observe membrane voltage
#     h.setpointer(cell(0.5)._ref_v, 'temp_ref', observer)
#     observer.add_ref_to_group(1, i)


# # Make connections
# syns = []
# netcons = []
# for i in range(num_cells):
#     for j in np.random.choice(num_cells, 5, replace=False):
#         cell = cells[i]
#         syn = h.Exp2Syn(cell(0.5))
#         syn.g = 1
#         syn.e = 0

#         nc = h.NetCon(cell(0.5)._ref_v, syn, 0.0, 1.0, 1.0, sec=cell)
#         netcons.append(nc)

#         nc = h.NetCon(nstims[j], syn, 0.0, 1.0, 1.0)
#         netcons.append(nc)


h.dt = 0.025
h.v_init = -68
h.celsius = 35
h.finitialize()
h.tstop = 100
h.run()

# For near-infinite loop:
# h.continuerun(1e12)