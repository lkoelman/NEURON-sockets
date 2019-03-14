# C Programming in MOD files

Instructive examples:

- `NetStim.mod`
- `pattern.mod` (found in  nrn/src/nrnoc/pattern.mod)
- `feature.mod` (found in nrn/src/nrnoc/feature.mod)



Working with C code inside VERBATIM blocks:

- mechanism variables
    
    - variables declared in `PARAMETER`/`ASSIGNED` can be accessed as follows:
    - `varname` is the value of the variable
    - `_p_varname` is a pointer to the variable


- inside a FUNCTION block:
    
    - `_l<func_name>` refers to the return value
    - `_l<varname>` refers to any LOCAL variable
    - `_l<argname>` refers to any FUNCTION argument
    
    - getting the i-th argument: `*getarg(i)`
    
    - there are special functions to retrieve function arguments
      as specific types
        + e.g. `vector_arg()` for Hoc Vector
        + e.g. `nrn_random_arg()` for Hoc Random


- memory management

    + `emalloc()` and `ecalloc()` are wrappers around malloc() and calloc()
      that check if enough memory is available