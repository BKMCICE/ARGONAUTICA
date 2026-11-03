/* Supplement the application's normal linker script, only for STACK_PROBE=1. */
ASSERT(__stack_top >= __stack_probe_bytes &&
       __heap_start <= __stack_top - __stack_probe_bytes,
       "Stack probe window overlaps static application data")
