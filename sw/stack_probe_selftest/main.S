/* CASE0 writes nothing; CASE1 touches exactly 512 bytes below stack top;
 * CASE2 intentionally corrupts one bottom-guard word, without using that SP.
 * All return 0 so the RTL exit result remains separate from guard status. */
    .section .text, "ax"
    .globl main
main:
#if PROBE_CASE == 1
    addi sp, sp, -512
    sw zero, 0(sp)
    addi sp, sp, 512
#elif PROBE_CASE == 2
    la t0, __stack_top
    li t1, 4092
    sub t0, t0, t1
    sw zero, 0(t0)
#elif PROBE_CASE != 0
#error "Unknown probe self-test case"
#endif
    li a0, 0
    ret
