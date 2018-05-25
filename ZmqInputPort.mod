COMMENT

TODO: description

Written by Lucas Koelman

INSTALL
-------

- install libzmq using your package manager
- compile mod file using following command:

nrnivmodl -incflags -llibzmq -loadflags -l:libzmq.a


EXAMPLE
-------

group1_refs = h.Vector([nc1._ref_weight[0], nc2._ref_weight[0]])
group1_id = 1

group2_refs = h.Vector([syn3._ref_gmax, syn4._ref_gmax])
group2_id = 2

port = h.ZmqInputPort()
port.port_number = 5555
port.add_target_group(group1_refs, group1_id)
port.add_target_group(group2_refs, group2_id)


DEVNOTES
-----------

TODO:

- Can use one input port that does play() of received value
  into the weight referenced by POINTER
    + can create one such object per host, and connect all
      the weights of synapses on same host

Inspired by following examples:

- NetStim.mod
- pattern.mod (found in  nrn/src/nrnoc/pattern.mod)
- feature.mod (found in nrn/src/nrnoc/feature.mod)
- extra NMODL blocks declared in nrn/src/nmodl/parse1.y

Working with C code inside VERBATIM blocks:

- inside functions, "_l<func_name>" refers to the return value

ENDCOMMENT

NEURON {
    ARTIFICIAL_CELL ZmqInputPort
    POINTER donotuse_context
    POINTER donotuse_socket
    POINTER target_groups
    RANGE check_interval, port_number, blocking_socket
    GLOBAL context_num_users, context_initialized
}

VERBATIM
#include <zmq.h>
// Following headers are included transitively in generated .c file:
// #include <stdio.h>
// #include <stdlib.h>
// #include <assert.h>
// #include <math.h>
// #include <string.h>

// Forward declare some useful NEURON functions
extern int ifarg(int iarg);
extern double* vector_vec(void* vv);
extern int vector_capacity(void* vv);
extern void* vector_arg(int iarg);

// Container for a group of target variables to control
typedef struct {
    int group_id;
    void* ref_vec; // Hoc Vector containing references to controlled variables
} TargetGroup;

#define GETGROUPS TargetGroup** grps = (TargetGroup**)(&(_p_target_groups))

ENDVERBATIM

PARAMETER {
    check_interval = 5 (ms) : refresh period
    port_number = 5555
    blocking_socket = 0
}

ASSIGNED {
    on
    socket_initialized : initial value before INITIAL is 0
    context_initialized
    context_num_users

    donotuse_context
    donotuse_socket
    target_groups
}

INITIAL {

VERBATIM
    static void* context;

    if (!context_initialized) {
        context_initialized = 1;
        
        // If we make multiple instances, only use one context.
        // - make context GLOBAL
        // - assign once (see feature.mod)
        // see http://zguide.zeromq.org/page:all#Getting-the-Context-Right
        context = zmq_ctx_new();
    }
    // Each instance pointer refers to the static one
    _p_donotuse_context = context;
    context_num_users = context_num_users + 1;
    
    // Make sure this is only executed once
    if (!socket_initialized) {

        // Assign to ASSIGNED pointer variables
        // _p_donotuse_context = zmq_ctx_new();
        _p_donotuse_socket = zmq_socket(_p_donotuse_context, ZMQ_SUB);

        // We use PUB-SUB pattern where this is the subscriber,
        // so we use zqm_connect() and the publisher uses zmq_bind()
        char addr_buffer[21];
        sprintf(addr_buffer, "tcp://localhost:%d", (int)port_number);
        int rc = zmq_connect(_p_donotuse_socket, addr_buffer);
        assert(rc==0);
        fprintf(stderr, "Set up ZMQ socket with return code %d at address %s.\n", rc, addr_buffer);
        
        // SUB socket filters out all messages initially -> need to add filters
        // However, an empty filter value with length argument zero subscribes to all messages
        rc = zmq_setsockopt(_p_donotuse_socket, ZMQ_SUBSCRIBE, NULL, 0);
        assert(rc==0);
    }

ENDVERBATIM

    socket_initialized = 1
    on = 0
    net_send(check_interval, 1)
}

CONSTRUCTOR {
VERBATIM {
    // Can hold maximum of 20 target groups
    GETGROUPS;
    int max_groups = 20;
    TargetGroup* tgroups = (TargetGroup*)hoc_Emalloc(max_groups * sizeof(TargetGroup));
    hoc_malchk();
    *grps = tgroups;

    // Initialize each group with group_id and empty reference vector
    int igrp;
    for(igrp = 0; igrp < max_groups; ++igrp) {
        tgroups[igrp].group_id = igrp;
        tgroups[igrp].ref_vec = (void*)0;
    }

}
ENDVERBATIM
}


DESTRUCTOR {
VERBATIM {
    // cleanup code, e.g. free(mydata);
    context_num_users = context_num_users-1;
    zmq_close(_p_donotuse_socket);
    if (context_num_users == 0 && context_initialized){
        zmq_ctx_destroy(_p_donotuse_context);
        context_initialized = 0;
    }
}
ENDVERBATIM
}

FUNCTION handle_messages() {
VERBATIM
 {
    fprintf(stderr, "Handling ZMQ messages.\n");

    // Default return value
    _lhandle_messages = 0;

    // Reive message in pre-agreed format
    int num_ints = 2;
    int buffer[num_ints]; // message consists of two integers
    int flags = blocking_socket? 0 : ZMQ_DONTWAIT;
    int size = zmq_recv(_p_donotuse_socket, buffer, num_ints*sizeof(int), flags);
    
    if (size == -1) {
        fprintf(stderr, "Received nothing.\n");
    } else if (size < num_ints) {
        fprintf(stderr, "Only got %d bytes.\n", size);
    } else {
        if (size > num_ints)
            fprintf(stderr, "Received more bytes than expected.\n");

        // Send spikes on depending on message contents
        fprintf(stderr, "Got message [%d|%d].\n", buffer[0], buffer[1]);
        if (buffer[1] > 0)
            _lhandle_messages = 1;
    }
 }
ENDVERBATIM
}

: Handle net events
:
: The built-in function net_event(t) delivers an event to the targets of the 
: NetCon objects with this object as their source
:
: The built-in function net_send(delay, flag) delivers an event at time t+delay 
: with flag value 'flag'
:
: @param    w : float
:           NetCon.weight[0] set on the NetCon that connects to this object
:           (additional weights are retrieved by specifying additional args)
:
: @param    flag : int
:           Value of second argument passed to net_send()
:
NET_RECEIVE (w) {
    LOCAL dospike
    dospike = 0

    if (flag == 0) { : 0 is used for external events

    }
    if (flag == 1) { : message from INITIAL
        if (on == 0) { : turn on
            on = 1
            dospike = handle_messages()
            net_send(check_interval, 2) : prepare for next sample
        } else {
            if (on == 1) { : turn off
                on = 0
            }
        }
    }
    if (flag == 2) { : message from NET_RECEIVE
        if (on == 1) {
            : TODO: use net_event(t) when message received
            dospike = handle_messages()
            net_send(check_interval, 2) : prepare for next sample
        }
    }

    if (dospike) {
        net_event(t)
    }
}