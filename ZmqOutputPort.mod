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




DEVNOTES
-----------

TODO:

- collect all incoming spikes in buffer, and write it to socket
  with fixed period. This prevents to many socket calls.


Inspired by following examples:

- NetStim.mod
- pattern.mod (found in  nrn/src/nrnoc/pattern.mod)
- feature.mod (found in nrn/src/nrnoc/feature.mod)
- extra NMODL blocks declared in nrn/src/nmodl/parse1.y



ENDCOMMENT

NEURON {
    ARTIFICIAL_CELL ZmqOutputPort
    POINTER donotuse_context
    POINTER donotuse_socket
    POINTER target_groups
    POINTER temp_ref : temporary fix for difficulty passing pointer
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

// Linked list node for storing refs to controlled parameters
typedef struct node {
    double initial_val;  // save initial value of controlled variable
    double* hoc_ref;      // hoc reference to controlled variable
    struct node* next;  // next node in linked list
} GroupNode;

// Container for a group of target variables to control
typedef struct {
    int group_id;       // Unused for the time being, just use index as identifier.
    // void* ref_vec;   // Hoc Vector containing references to controlled variables
    GroupNode* ref_list; // Linked list containing references to controlled variables
} TargetGroup;

#define GETGROUPS TargetGroup** grps = (TargetGroup**)(&(_p_target_groups))

// Max number of controlled groups (arbitrary)
static const int MAX_GROUPS = 20;
static const int GROUP_MAX_CAP = 100;

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
    temp_ref

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
        sprintf(addr_buffer, "tcp://*:%d", (int)port_number);
        int rc = zmq_bind(_p_donotuse_socket, addr_buffer);
        assert(rc==0);
        fprintf(stderr, "Set up ZMQ socket with return code %d at address %s.\n", rc, addr_buffer);
    }

ENDVERBATIM

    socket_initialized = 1
    on = 0
    net_send(check_interval, 1)
}

CONSTRUCTOR {
VERBATIM {
    // TODO: make the event buffer
    GETGROUPS; // set local var TargetGroup** grps
    TargetGroup* tgroups = emalloc(MAX_GROUPS * sizeof(TargetGroup));
    *grps = tgroups;

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

    // TODO: clear the event buffer
}
ENDVERBATIM
}



FUNCTION handle_messages() {
    LOCAL group_id, weight
    : Read messages from socket and do modifications to controlled
    : variables if necessary.
VERBATIM
    fprintf(stderr, "Handling ZMQ messages.\n");

    // Default return value
    _lhandle_messages = 0;

    // Reive message in pre-agreed format
    int msg_len = 2;
    // TODO: make buffer as global var so we can write from NET_RECEIVE
    double buffer[msg_len]; // message consists of two integers
    size_t buf_size = msg_len * sizeof(double);
    // TODO: check available send flags
    int flags = blocking_socket? 0 : ZMQ_DONTWAIT;
    zmq_send(_p_donotuse_socket, buffer, buf_size, flags);
    
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
: @param    w : double
:           NetCon.weight[0] set on the NetCon that connects to this object
:           (additional weights are retrieved by specifying additional args)
:
: @param    flag : int
:           Value of second argument passed to net_send()
:
NET_RECEIVE (w) {

    if (flag == 0) { : 0 is used for external events
        :// TODO: write [t, weight] to buffer
        ://       - if buffer is full -> flush it
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
    if (flag == 2) { : self-message from NET_RECEIVE
        if (on == 1) {
            :// TODO: process the buffer -> flush to socket
            dospike = handle_messages()
            net_send(check_interval, 2) : prepare for next sample
        }
    }
}