"""
Test script for ZmqOutputVars.mod.
"""

import sys

from neuron import h
import numpy as np

h.load_file("stdlib.hoc") # Load the standard library
h.load_file("stdrun.hoc") # Load the standard run library

################################################################################
# Cell from ball-and-stick tutorial
# https://neuron.yale.edu/neuron/static/docs/neuronpython/ballandstick1.html

soma = h.Section(name='soma')
dend = h.Section(name='dend')
dend.connect(soma(1))

soma.L = soma.diam = 12.6157 # Makes a soma of 500 microns squared.
dend.L = 200 # microns
dend.diam = 1 # microns

for sec in h.allsec():
    sec.Ra = 100    # Axial resistance in Ohm * cm
    sec.cm = 1      # Membrane capacitance in micro Farads / cm^2

# Insert active Hodgkin-Huxley current in the soma
soma.insert('hh')
for seg in soma:
    seg.hh.gnabar = 0.12  # Sodium conductance in S/cm2
    seg.hh.gkbar = 0.036  # Potassium conductance in S/cm2
    seg.hh.gl = 0.0003    # Leak conductance in S/cm2
    seg.hh.el = -54.3     # Reversal potential in mV

# Insert passive current in the dendrite
dend.insert('pas')
for seg in dend:
    seg.pas.g = 0.001  # Passive conductance in S/cm2
    seg.pas.e = -65    # Leak reversal potential mV

# stim = h.IClamp(dend(1))
# stim.delay = 50
# stim.dur = 200
# stim.amp = .1

stim = h.NetStim()
stim.number = 1e12
stim.start = 5
stim.noise = 1
stim.interval = 50

syn = h.Exp2Syn(soma(0.5))
syn.e = 0
syn.tau1 = 5
syn.tau2 = 12

nc = h.NetCon(stim, syn)
nc.weight[0] = gmax = 7.5e-2
nc.delay = 1.0

istim = h.NetStim()
istim.number = 1e12
istim.start = 5
istim.noise = 1
istim.interval = 50

isyn = h.Exp2Syn(soma(0.5))
isyn.e = -80
isyn.tau1 = 5
isyn.tau2 = 20

inc = h.NetCon(istim, isyn)
inc.weight[0] = gmax
inc.delay = 1.0

# Insert simulation rate controller
ratectl = h.SimRateCtl(soma(0.5))
ratectl.rate = 10 # 10 x slower than real-time


################################################################################
# Add Observer

observer = h.ZmqOutputVars()
observer.port_number = 5557
observer.use_icp = 0
observer.sample_period = 0.1
observer.flush_period = 10.0

h.setpointer(soma(0.5)._ref_v, 'temp_ref', observer)
observer.add_ref_to_group(1, 1.0)

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

dryrun = sys.argv[-1] == '--dry-run'
if dryrun:
    vvec = h.Vector()
    vvec.record(soma(0.5)._ref_v)
    duration = 500
else:
    duration = 1e12

try:
    h.dt = 0.025
    h.v_init = -68
    h.celsius = 35
    h.finitialize()

    pause_interval = 100.0
    while(h.t < duration):
        # h.tstop = duration
        # h.run()

        # run() calls init() but continuerun() does not 
        h.continuerun(h.t + pause_interval)

    if dryrun:
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots()
        v = vvec.as_numpy()
        ax.plot(np.arange(v.size) * h.dt, v)
        plt.show(block=True)

    # For near-infinite loop:
    # h.continuerun(1e12)
except KeyboardInterrupt: # catches CTRL+C signal
    sys.exit()