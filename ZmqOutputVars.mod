COMMENT

Observe Hoc variables as they change during a simulation and publish their
values and sample times to a network socket.

Publishes a stream of packets of size 3*sizeof(double) to a socket bound to 
a port of choice. The packets consist of (variable_id, sample_time, sample_value)
where each value is an 8-byte double.

Written by Lucas Koelman

INSTALL
-------

- install libzmq using your package manager
- compile mod file using following command:

nrnivmodl -incflags -llibzmq -loadflags -l:libzmq.a


EXAMPLE
-------

Example in Python:

TODO: example

DEVNOTES
-----------

Inspired by following examples:

- NetStim.mod
- pattern.mod (found in  nrn/src/nrnoc/pattern.mod)
- feature.mod (found in nrn/src/nrnoc/feature.mod)
- extra NMODL blocks declared in nrn/src/nmodl/parse1.y


ENDCOMMENT


NEURON {
    ARTIFICIAL_CELL ZmqOutputVars

    POINTER donotuse_context
    POINTER donotuse_socket
    POINTER donotuse_ebuffer    : event buffer for internal use
    POINTER target_groups
    POINTER temp_ref            : temporary fix for difficulty passing pointer
    
    RANGE sample_period, flush_period, port_number, blocking_socket, use_icp
    GLOBAL context_num_users, context_initialized
}

VERBATIM
#include <zmq.h>
// Headers automatically included (transitively) in generated .c file:
// #include <stdio.h>
// #include <stdlib.h>
// #include <assert.h>
// #include <math.h>
// #include <string.h>

// Linked list node for storing refs to observed hoc variables
typedef struct node {
    double var_id;      // user-specified identifer for the observed varialbe
    double* hoc_ref;    // hoc reference to observed variable
    struct node* next;  // next node in linked list
} GroupNode;

// Container for a group of target variables to observe
typedef struct {
    int group_id;       // Unused for the time being, just use index as identifier.
    GroupNode* ref_list; // Linked list containing references to controlled variables
} TargetGroup;

#define GETGROUPS TargetGroup** grps = (TargetGroup**)(&(_p_target_groups))

// Max number of observed groups (arbitrary)
static const int MAX_GROUPS = 20;

// Provide space to store all samples in between flush_period so we
// don't cause flushes in between and slow donwn simulation.
// Space required is msg_len * num_observed * flush_period / sample_period
//                =     3    *     ~20      *      5       /      .05
//                = 6000
static const int EVENT_BUF_SIZE = 6000;

ENDVERBATIM

PARAMETER {
    sample_period = 0.1 (ms): sample period for observed variables
    flush_period = 5.0 (ms) : flush period to send data to socket
    port_number = 5555
    blocking_socket = 0
    use_icp = 0             : use ICP rather than TCP protocol for communication
}

ASSIGNED {
    on
    socket_initialized      : initial value before INITIAL is 0
    context_initialized
    context_num_users
    temp_ref
    ebuf_next_pos           : next free position in event buffer

    donotuse_context
    donotuse_socket
    donotuse_ebuffer
    target_groups
}


CONSTRUCTOR {
VERBATIM {
    // Snippet based on pattern.mod
    GETGROUPS; // set local var TargetGroup** grps
    TargetGroup* tgroups = emalloc(MAX_GROUPS * sizeof(TargetGroup));
    *grps = tgroups;

    // Initialize each group with group_id and empty reference vector
    int i;
    for(i = 0; i < MAX_GROUPS; ++i) {
        tgroups[i].group_id = i;

        // tgroups[i].ref_list = NULL;
        // Make head of linked list
        tgroups[i].ref_list = emalloc(sizeof(GroupNode));
        tgroups[i].ref_list->var_id = 0.0;
        tgroups[i].ref_list->hoc_ref = NULL;
        tgroups[i].ref_list->next = NULL;
    }

    // Buffer to hold samples before sending to socket
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

    fprintf(stderr, "Freeing sample buffer...\n");
    free(_p_donotuse_ebuffer);

    // Free containers for controlled variable groups
    fprintf(stderr, "Freeing linked lists...\n");
    GETGROUPS; // set local var TargetGroup** grps
    TargetGroup* groups = *grps;
    int i;
    for(i = 0; i < MAX_GROUPS; ++i) {
        // First free entire linked list
        GroupNode* current = groups[i].ref_list;
        GroupNode* next_node;
        while (current != NULL) {
            // fprintf(stderr, "Freed one list for group %d\n", i);
            next_node = current->next;
            free(current);
            current = next_node;
        }
        // fprintf(stderr, "Freed list for group %d\n", i);
    }

    fprintf(stderr, "Freeing groups...\n");
    free(groups);
}
ENDVERBATIM
}


INITIAL {

VERBATIM
    static void* context;

    if (!context_initialized) {
        context_initialized = 1;
        
        // If we make multiple instances, only use one context.
        context = zmq_ctx_new();
    }
    // Each instance pointer refers to the static one
    _p_donotuse_context = context;
    context_num_users = context_num_users + 1;
    
    // Make sure this is only executed once
    if (!socket_initialized) {

        // Assign to ASSIGNED pointer variables
        _p_donotuse_socket = zmq_socket(_p_donotuse_context, ZMQ_PUB);

        // We use PUB-SUB pattern where this is the subscriber,
        // so we use zqm_connect() and the publisher uses zmq_bind()
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

    socket_initialized = 1
    on = 0
    net_send(sample_period, 1)  : turn on and start sampling
    net_send(flush_period, 3)   : start flush cycle
}


FUNCTION add_ref_to_group(grp_id, var_id) {
VERBATIM
    uint32_t group_id = (uint32_t) _lgrp_id;
    assert(group_id < MAX_GROUPS);
    
    GETGROUPS; // set local var TargetGroup** grps
    TargetGroup* groups = *grps;
    TargetGroup  target = groups[group_id];

    // Look for end of linked list and append controlled variable
    GroupNode* current = target.ref_list;
    while (current->next != NULL) {
        current = current->next;
    }

    current->next = emalloc(sizeof(GroupNode));
    current->next->var_id = _lvar_id;
    current->next->hoc_ref = _p_temp_ref;

    // fprintf(stderr, "Added ref to group %d\n", group_id);
ENDVERBATIM
}


VERBATIM

// Size of samples (number of double vals)
static int msg_len = 3;

/**
 * Flush the event buffer into the socket and reset position.
 */
static int flush_event_buffer() {
    int retval = 0;

    // No relevant flags for PUB send socket
    size_t msg_size = ebuf_next_pos * sizeof(double);
    int sent_size = zmq_send(_p_donotuse_socket, _p_donotuse_ebuffer, msg_size, 0);
    

    if (sent_size != msg_size) {
        fprintf(stderr, "Sending of event buffer failed with error code %d.\n"
                        "%f events in buffer will be discarded.", sent_size, ebuf_next_pos/msg_len);
        retval = 1;
    } else {
        fprintf(stderr, "Flushed %f events to socket.\n", ebuf_next_pos/msg_len);
    }

    ebuf_next_pos = 0;
    return retval;
}

/**
 * Append an event received at time t to buffer.
 * If the buffer is full, flush it to socket first.
 */
static void append_to_buffer(double var_id, double time, double value) {

    // Assume buffer flushed if not enough space
    int pos = (int)ebuf_next_pos;
    _p_donotuse_ebuffer[pos] = var_id;
    _p_donotuse_ebuffer[pos+1] = time;
    _p_donotuse_ebuffer[pos+3] = value;
    ebuf_next_pos = (float)(pos + msg_len);

    // If buffer is full -> flush it
    if (ebuf_next_pos > (EVENT_BUF_SIZE - msg_len)) {
        flush_event_buffer();
    }
}


/**
 * Sample observed variables of all groups.
 */
static void sample_all_groups() {
    GETGROUPS; // set local var TargetGroup** grps
    TargetGroup* groups = *grps;

    int i;
    for(i = 0; i < MAX_GROUPS; ++i) {
        // First free entire linked list
        GroupNode* current = groups[i].ref_list;
        while (current != NULL) {
            if (current->hoc_ref != NULL) {
                double sample = *(current->hoc_ref);
                append_to_buffer(current->var_id, t, sample);
            }
            current = current->next;
            // fprintf(stderr, "Sampled one var in group %d\n", group_id);
        }
    }
}
ENDVERBATIM


NET_RECEIVE (w) {

    if (flag == 0) { : 0 is used for external events
VERBATIM
        fprintf(stderr, "Received event with weight %f\n", _args[0]);
ENDVERBATIM
    }
    if (flag == 1) { : message from INITIAL
        if (on == 0) { : turn on and start sampling
            on = 1
VERBATIM
            sample_all_groups();
ENDVERBATIM
            net_send(sample_period, 2)
        } else {
            on = 0
        }
    }
    if (flag == 2 && on == 1) { : self-message to sample variables
VERBATIM
        sample_all_groups();
ENDVERBATIM
        net_send(sample_period, 2)
    }
    if (flag == 3 && on == 1) { : self-message to flush buffer
VERBATIM
        // Periodic flush, after N*flush_period
        if (ebuf_next_pos != 0)
            flush_event_buffer();
ENDVERBATIM
        net_send(flush_period, 3) : prepare for next sample
    }
}