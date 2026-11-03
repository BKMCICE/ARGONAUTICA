    .section .text.init,"ax"
    .global _start
_start:
    li sp,0x10000
    la t0,trap_entry
    csrw mtvec,t0
    call main
    li t0,0x7000
    sw a0,0(t0)
    li t0,0x600d0001
    li t1,0xa5
    beq a0,t0,1f
    li t1,0xe0
1:  li t0,0x40001000
    sw t1,0(t0)
2:  j 2b
    .global readonly_store
readonly_store:
    sw zero,0(a0)
    ret
    .align 2
trap_entry:
    addi sp,sp,-16
    sw t0,0(sp)
    sw t1,4(sp)
    sw t2,8(sp)
    csrr t0,mcause
    li t1,7
    bne t0,t1,bad_trap
    csrr t2,mtval
    li t1,0x80400000
    bne t2,t1,bad_trap
    li t1,0x7008
    sw t0,0(t1)
    csrr t0,mepc
    addi t0,t0,4
    csrw mepc,t0
    lw t0,0(sp)
    lw t1,4(sp)
    lw t2,8(sp)
    addi sp,sp,16
    mret
bad_trap:
    li t1,0xdead0000
    or t0,t0,t1
    li t1,0x7000
    sw t0,0(t1)
    li t1,0x40001000
    li t0,0xe0
    sw t0,0(t1)
3:  j 3b
