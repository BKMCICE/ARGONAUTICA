/* Tiny DDR image for the UART bootloader system test. */
    .section .text.init, "ax"
    .globl _start
_start:
    lui t0, 0x0000f
    addi t1, zero, 1
    sw t1, 0(t0)
1:  j 1b
