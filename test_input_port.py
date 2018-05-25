from neuron import h

h.load_file("stdlib.hoc") # Load the standard library
h.load_file("stdrun.hoc") # Load the standard run library

sec = h.Section()
port = h.ZmqInputPort()
port.blocking_socket = 1
port.port_number = 5559

h.finitialize()
h.tstop = 100
h.run()

# For near-infinite loop:
# h.continuerun(1e12)