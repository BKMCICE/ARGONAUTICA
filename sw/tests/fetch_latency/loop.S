/* Position-independent loop copied byte-for-byte to TCM and cached DDR.
 * Each iteration retires 32 NOPs, ADDI, and BNE; RET executes once. */
    .section .text.fetch_template, "ax", @progbits
    .option norvc
    .balign 4
    .globl fetch_template_start
    .globl fetch_template_end
fetch_template_start:
    .rept 32
    nop
    .endr
    addi a0, a0, -1
    bnez a0, fetch_template_start
    ret
fetch_template_end:
