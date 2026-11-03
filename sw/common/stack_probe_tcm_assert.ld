/* A TCM stack is disjoint from the higher-addressed DDR static region. */
ASSERT(__stack_top >= __stack_probe_bytes &&
       __stack_top - __stack_probe_bytes >= __stack_bottom,
       "Stack probe window exceeds reserved TCM stack")
