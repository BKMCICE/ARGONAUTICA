/* Optional diagnostic: write watermark, not an exact worst-case SP bound. */
#ifndef RV_STACK_PROBE_H
#define RV_STACK_PROBE_H
#ifndef STACK_PROBE_BYTES
#define STACK_PROBE_BYTES 65536
#endif
#ifndef STACK_PROBE_GUARD_BYTES
#define STACK_PROBE_GUARD_BYTES 256
#endif
#define STACK_PROBE_PATTERN 0xa5a5a5a5
#if STACK_PROBE_BYTES < 512 || (STACK_PROBE_BYTES % 16)
#error "STACK_PROBE_BYTES must be at least 512 and a multiple of 16"
#endif
#if STACK_PROBE_GUARD_BYTES < 16 || (STACK_PROBE_GUARD_BYTES % 4) || STACK_PROBE_GUARD_BYTES >= STACK_PROBE_BYTES
#error "Invalid STACK_PROBE_GUARD_BYTES"
#endif
#endif
