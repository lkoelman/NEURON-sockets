COMMENT

Set the value of Hoc variables (referenced by pointer) during the simulation
based on incoming network packages.

ZmqInputPort listens on a network socket for messages in the 
format (group_id, value) and assigns value to all Hoc variables referenced
by group_id.

Written by Lucas Koelman

INSTALL
-------

- install libzmq using your package manager
- compile mod file using following command:

nrnivmodl -incflags -llibzmq -loadflags -l:libzmq.a


EXAMPLE
-------

Example in Python:

>>> group1_refs = h.Vector([nc1._ref_weight[0], nc2._ref_weight[0]])
>>> group1_id = 1
>>> 
>>> group2_refs = h.Vector([syn3._ref_gmax, syn4._ref_gmax])
>>> group2_id = 2
>>> 
>>> port = h.ZmqInputPort()
>>> port.port_number = 5555
>>> port.add_target_group(group1_refs, group1_id)
>>> port.add_target_group(group2_refs, group2_id)


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

- mechanism variables
    
    - variables declared in PARAMETER/ASSIGNED can be accessed as follows:
    - "varname" is the value of the variable
    - "_p_varname" is a pointer to the variable


- inside a FUNCTION block:
    
    - "_l<func_name>" refers to the return value
    - "_l<varname>" refers to any LOCAL variable
    - "_l<argname>" refers to any FUNCTION argument
    
    - getting the i-th argument: *getarg(i)
    
    - there are special functions to retrieve function arguments
      as specific types
        + e.g. vector_arg() for Hoc Vector
        + e.g. nrn_random_arg() for Hoc Random


- memory management

    + emalloc() and ecalloc() are wrappers around malloc() and calloc()
      that check if enough memory is available

ENDCOMMENT

NEURON {
    ARTIFICIAL_CELL ZmqInputPort
    POINTER donotuse_context
    POINTER donotuse_socket
    POINTER target_groups
    POINTER temp_ref : temporary fix for difficulty passing pointer
    RANGE check_interval, port_number, blocking_socket, use_icp
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

// Forward declare some useful NEURON functions
// extern int ifarg(int iarg);
// see <ivocvect.h>
// extern double* vector_vec(void* vv);        // vector to double*
// extern void* vector_arg(int iarg);          // function argument to vector
// extern int vector_capacity(void* vv);       // number of occupied slots
// extern int vector_buffer_size(void* vv);    // total number of slots
// extern void vector_resize(void*, int max);  // increase max capacity by resizing buffer
// extern void vector_append(void* vv, double x); // increment capacity and append
// extern void* vector_new0();                 // init with zero capacity
// extern void* vector_new1(int buffer_size);  // init with max capacity
// extern void vector_delete(void* vv);        // free memory

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
    use_icp = 0             : use ICP rather than TCP protocol for communication
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
        // tgroups[i].ref_vec = (void*)0;

        // Make head of linked list
        // tgroups[i].ref_list = NULL;
        tgroups[i].ref_list = emalloc(sizeof(GroupNode));
        tgroups[i].ref_list->initial_val = 0.0;
        tgroups[i].ref_list->hoc_ref = NULL;
        tgroups[i].ref_list->next = NULL;
    }

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

    // Free containers for controlled variable groups
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
    // Free the group container
    free(groups);
    // fprintf(stderr, "Freed group containers\n");
}
ENDVERBATIM
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
        char *protocol = use_icp? "icp" : "tcp";
        sprintf(addr_buffer, "%s://localhost:%d", protocol, (int)port_number);

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


FUNCTION add_ref_to_group() { : if we define arguments it expects double
VERBATIM
    uint32_t group_id = (uint32_t) *getarg(1);
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
    current->next->initial_val = temp_ref;
    current->next->hoc_ref = _p_temp_ref;

    // fprintf(stderr, "Added ref to group %d\n", group_id);

    // Same using Vector instead of linked list
    // NOTE: need to cast to safe type first, uintptr_t from <stdint.h> is made for this
    // sprintf(stderr, "Sizes are: uintptr_t:%d, double:%d", (int)sizeof(uintptr_t), (int)sizeof(double));
    // uintptr_t ref_address1 = (uintptr_t) _p_temp_ref;
    // double ref_address = (double) ref_address1;
    // if (target.ref_vec == NULL) { // NULL is (void*)0
    //     // TODO: this doesn't work as I thought. Fix it.
    //     // target.ref_vec = vector_new1(GROUP_MAX_CAP);
    //     target.ref_vec = vector_new0();
    //     // vector_resize(target.ref_vec, GROUP_MAX_CAP);
    //     fprintf(stderr, "Vector with capacity %d and buffer size %d", vector_capacity(target.ref_vec), vector_buffer_size(target.ref_vec));
    //     vector_append(target.ref_vec, ref_address);
    //     fprintf(stderr, "Vector with capacity %d and buffer size %d", vector_capacity(target.ref_vec), vector_buffer_size(target.ref_vec));
    // } else {
    //     int cap = vector_capacity(target.ref_vec);
    //     if (cap == vector_buffer_size(target.ref_vec));
    //         vector_resize(target.ref_vec, cap + GROUP_MAX_CAP);
    //     vector_append(target.ref_vec, ref_address);
    // }
ENDVERBATIM
}


: FUNCTION modify_group(group_id, weight) {
    : Modify the controlled variables for the group.
    :
    : @param    1 : group_id (uint)
    :           First argument is the  group ID which must be < MAX_GROUPS.
    :
    : @param    2 : weight (float)
    :           Second argument is the value assigned to the controlled
    :           variables.
VERBATIM
// Made into C function to avoid indirection through Hoc function
void modify_group(double _lgroup_id, double _lweight) {

    int group_id = (int)_lgroup_id;
    assert(group_id < MAX_GROUPS);

    // Get group by identifier
    GETGROUPS; // set local var TargetGroup** grps
    TargetGroup* groups = *grps;
    TargetGroup  target = groups[group_id];

    // Modify all controlled variables
    GroupNode* current = target.ref_list;
    while (current != NULL) {
        if (current->hoc_ref != NULL) {
            double new_val = _lweight * (current->initial_val);
            *(current->hoc_ref) = new_val;
        }
        current = current->next;
        // fprintf(stderr, "Modified one item in group %d\n", group_id);
    }

    // Same using Vector instead of linked list
    // int size = vector_capacity(target.ref_vec);
    // // NOTE: vector_vec() returns float*, but if we fill the vector
    // // with pointers to scalar variables (float*), we can use float**
    // double** refvec = (double**) vector_vec(target.ref_vec);
    // int i;
    // for (i = 0; i < size; i++) {
    //     // POINTER should be modifiable, see STDP weight adjuster mechanisms
    //     // src/ivoc/ivocvect.cpp -> src/nrniv/vrecord.cpp -> src/nrncvode/vrecitem.h
    //     *(refvec[i]) = _lweight;
    // }
}
ENDVERBATIM
: } : END FUNCTION


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
    double buffer[msg_len]; // message consists of two integers
    size_t buf_size = msg_len * sizeof(double);
    int flags = blocking_socket? 0 : ZMQ_DONTWAIT;
    // TODO: check if ZMQ_DONTWAIT defers filling of the buffer -> if so use it in next iteration
    int size = zmq_recv(_p_donotuse_socket, buffer, buf_size, flags);
    
    if (size == -1) {
        fprintf(stderr, "Received nothing.\n");
    } else if (size < buf_size) {
        fprintf(stderr, "Only got %d bytes.\n", size);
    } else {
        if (size > buf_size)
            fprintf(stderr, "Received more bytes than expected.\n");

        // Send spikes on depending on message contents
        fprintf(stderr, "Got message [%f|%f].\n", buffer[0], buffer[1]);
        _lgroup_id = buffer[0];
        _lweight = buffer[1];

        modify_group(_lgroup_id, _lweight);
        _lhandle_messages = 1;
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
: @param    w : double
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