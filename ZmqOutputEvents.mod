COMMENT

Listen to NEURON events (spikes, ...) and publish them on a network socket.

Written by Lucas Koelman

INSTALL
-------

- install libzmq using your package manager
- compile mod file using following command:

nrnivmodl -incflags -llibzmq -loadflags -l:libzmq.a


EXAMPLE
-------

Example in Python:


>>> observer = h.ZmqOutputEvents()
>>> observer.port_number = 5559
>>> observer.use_icp = 0
>>> 
>>> stims, netcons = [], []
>>> num_stims = 5
>>> for i in range(num_stims):
>>>     stim = h.NetStim()
>>>     stims.append(stim)
>>> 
>>>     stim.number = 1e9
>>>     stim.start = 5
>>>     stim.noise = 1
>>>     stim.interval = 10 + i
>>> 
>>>     nc = h.NetCon(stim, observer)
>>>     nc.weight[0] = i # weight functions as identifier
>>>     netcons.append(nc)


DEVNOTES
-----------

Inspired by following examples:

- NetStim.mod
- pattern.mod (found in  nrn/src/nrnoc/pattern.mod)
- feature.mod (found in nrn/src/nrnoc/feature.mod)
- extra NMODL blocks declared in nrn/src/nmodl/parse1.y



ENDCOMMENT

NEURON {
    ARTIFICIAL_CELL ZmqOutputEvents

    POINTER donotuse_context
    POINTER donotuse_socket
    POINTER donotuse_ebuffer    : event buffer for internal use

    RANGE flush_interval, port_number, use_icp
    GLOBAL context_num_users, context_initialized
}

VERBATIM
#include <zmq.h>

// Max number of events collected between flushes
static const int EVENT_BUF_SIZE = 200;

ENDVERBATIM

PARAMETER {
    flush_interval = 5 (ms) : period between socket send
    port_number = 5555
    use_icp = 0             : use ICP rather than TCP protocol for communication
}

ASSIGNED {
    on
    socket_initialized      : initial value before INITIAL is 0
    context_initialized
    context_num_users
    ebuf_next_pos           : next free position in event buffer

    donotuse_context
    donotuse_socket
    donotuse_ebuffer
}

: Constructor is called only once, unlike INITIAL
CONSTRUCTOR {
VERBATIM {
    // Buffer to hold incoming events before sending to socket
    double* ebuffer = emalloc(EVENT_BUF_SIZE * sizeof(double));
    _p_donotuse_ebuffer = ebuffer;

}
ENDVERBATIM
}


DESTRUCTOR {
VERBATIM {
    // Clean up ZMQ sockets
    context_num_users = context_num_users-1;
    zmq_close(_p_donotuse_socket);
    if (context_num_users == 0 && context_initialized){
        zmq_ctx_destroy(_p_donotuse_context);
        context_initialized = 0;
    }

    // clear the event buffer
    free(_p_donotuse_ebuffer);
}
ENDVERBATIM
}


INITIAL {

VERBATIM
    static void* context;

    if (!context_initialized) {
        context_initialized = 1;
        
        // If we make multiple instances, only use one context.
        // TODO: find out how we can re-use context from other mechanism
        context = zmq_ctx_new();
    }
    // Each instance pointer refers to the static one
    _p_donotuse_context = context;
    context_num_users = context_num_users + 1;
    
    // Make sure this is only executed once
    if (!socket_initialized) {

        // Assign to ASSIGNED pointer variables
        // _p_donotuse_context = zmq_ctx_new();
        _p_donotuse_socket = zmq_socket(_p_donotuse_context, ZMQ_PUB);

        // We use PUB-SUB pattern where this is the publisher,
        // so we use zqm_bind() and the subscribers uses zmq_connect()
        char addr_buffer[21];
        char *protocol = use_icp? "icp" : "tcp";
        sprintf(addr_buffer, "%s://*:%d", protocol, (int)port_number);
        
        int rc = zmq_bind(_p_donotuse_socket, addr_buffer);
        if (rc != 0) {
            fprintf(stderr, "Binding socket to %s failed with error code %d\n", addr_buffer, rc);
            assert(0);
        }
        fprintf(stderr, "Set up ZMQ socket with return code %d at address %s.\n", rc, addr_buffer);
    }

ENDVERBATIM

    ebuf_next_pos = 0
    socket_initialized = 1
    on = 0
    net_send(flush_interval, 1) : start the self-loop
}




VERBATIM
/**
 * Flush the event buffer into the socket and reset position.
 */
int flush_event_buffer() {
    int retval = 0;

    // No relevant flags for PUB send socket
    size_t msg_size = ebuf_next_pos * sizeof(double);
    int sent_size = zmq_send(_p_donotuse_socket, _p_donotuse_ebuffer, msg_size, 0);
    

    if (sent_size != msg_size) {
        fprintf(stderr, "Sending of event buffer failed with error code %d.\n"
                        "%f events in buffer will be discarded.", sent_size, ebuf_next_pos/2);
        retval = 1;
    } else {
        fprintf(stderr, "Flushed %f events to socket.\n", ebuf_next_pos/2);
    }

    ebuf_next_pos = 0;
    return retval;
}

// Size of events (number of double vals)
static int msg_len = 2;

/**
 * Append an event received at time t to buffer.
 * If the buffer is full, flush it to socket first.
 */
void append_to_buffer(double time, double value) {

    // Assume buffer flushed if not enough space
    int pos = (int)ebuf_next_pos;
    _p_donotuse_ebuffer[pos] = time;
    _p_donotuse_ebuffer[pos+1] = value;
    ebuf_next_pos = (float)(pos + msg_len);

    // If buffer is full -> flush it
    if (ebuf_next_pos > (EVENT_BUF_SIZE - msg_len)) {
        flush_event_buffer();
    }
}

ENDVERBATIM


NET_RECEIVE (w) {

    if (flag == 0) { : 0 is used for external events
VERBATIM
        // Only flush between self-events if buffer is full
        double weight = _args[0];
        append_to_buffer(t, weight);

ENDVERBATIM
    }
    if (flag == 1) { : message from INITIAL
        if (on == 0) { : turn on
            on = 1
VERBATIM
            // First flush, after 1*flush_period
            if (ebuf_next_pos != 0)
                flush_event_buffer();
ENDVERBATIM
            net_send(flush_interval, 2) : prepare for next sample
        } else {
            if (on == 1) { : turn off
                on = 0
            }
        }
    }
    if (flag == 2) { : self-message from NET_RECEIVE
        if (on == 1) {
            : flush buffer every flush_period
VERBATIM
            // Periodic flush, after N*flush_period
            if (ebuf_next_pos != 0)
                flush_event_buffer();
ENDVERBATIM
            net_send(flush_interval, 2) : prepare for next sample
        }
    }
}