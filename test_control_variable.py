from neuron import h

h.load_file("stdlib.hoc") # Load the standard library
h.load_file("stdrun.hoc") # Load the standard run library

sec1 = h.Section()
syn1 = h.Exp2Syn(sec1(0.5))
sec2 = h.Section()
syn2 = h.Exp2Syn(sec2(0.5))


port = h.ZmqInputPort()
port.blocking_socket = 1
port.port_number = 5559


h.setpointer(syn1._ref_g, 'temp_ref', port)
port.add_ref_to_group(1)

h.setpointer(syn2._ref_g, 'temp_ref', port)
port.add_ref_to_group(1)

h.finitialize()
h.tstop = 100
h.run()

# For near-infinite loop:
# h.continuerun(1e12)