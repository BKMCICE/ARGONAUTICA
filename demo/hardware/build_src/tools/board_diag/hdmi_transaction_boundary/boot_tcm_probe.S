    .option norvc
    .section .text.init,"ax"
    .global _start
_start:
    la t0,tcm_start
    li t1,0x8000
    la t2,tcm_end
copy_check:
    lw t3,0(t0)
    sw t3,0(t1)
    lw t4,0(t1)
    bne t3,t4,fail
    addi t0,t0,4
    addi t1,t1,4
    bltu t0,t2,copy_check
    .word 0x0000100f
    li t0,0x8000
    jalr zero,0(t0)
fail:
    li t0,0x40001000
    li t1,0xe1
    sw t1,0(t0)
1:  j 1b
    .align 2
    .global tcm_start,tcm_end,tcm_spin
tcm_start:
    lui t0,0x40001
    addi t1,zero,0xa6
    sw t1,0(t0)
tcm_spin:
    j tcm_spin
tcm_end:
