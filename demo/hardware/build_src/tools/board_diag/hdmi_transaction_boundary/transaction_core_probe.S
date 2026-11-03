    .option norvc
    .section .text.init,"ax"
    .global _start
_start:
    li sp,0x10000
    la t0,trap_handler
    csrw mtvec,t0
    li s7,0
    li s8,0
    li s9,0
    li s11,0
    li a3,100
    li a4,7
    li s0,0x40001000
    .global core_load_div
core_load_div:
    lw s1,0(s0)
    div s2,a3,a4
    li t0,0x11223344
    bne s1,t0,fail
    li t0,14
    bne s2,t0,fail
    .global core_pair_first
core_pair_first:
    lw s3,0(s0)
    .global core_pair_second
core_pair_second:
    lw s4,0(s0)
    li t0,0x11223344
    bne s3,t0,fail
    bne s4,t0,fail
    li s0,0x1000
    li t0,0x80ff7f01
    sw t0,0(s0)
    lb s3,3(s0)
    lbu s4,2(s0)
    lh s5,2(s0)
    lhu s6,0(s0)
    li t0,-128
    bne s3,t0,fail
    li t0,255
    bne s4,t0,fail
    li t0,0xffff80ff
    bne s5,t0,fail
    li t0,0x7f01
    bne s6,t0,fail
    li t0,0xaa
    sb t0,1(s0)
    li t0,0x1234
    sh t0,2(s0)
    lw s3,0(s0)
    li t0,0x1234aa01
    bne s3,t0,fail
    li t1,0x808
    csrw mie,t1
    li t1,8
    csrs mstatus,t1
    li s0,0x40002000
    li t0,1
    .global core_irq_store
core_irq_store:
    sw t0,0(s0)
    .global core_irq_next
core_irq_next:
    div s2,a3,a4
    addi s11,s11,1
    li t0,1
    bne s7,t0,fail
    bne s11,t0,fail
    li t0,14
    bne s2,t0,fail
    li s0,0x50000000
    li t5,0x55667788
    .global core_fault_load
core_fault_load:
    lw t5,0(s0)
    .global core_fault_next
core_fault_next:
    div s2,a3,a4
    li t0,0x55667788
    bne t5,t0,fail
    li t0,1
    bne s8,t0,fail
    li t0,14
    bne s2,t0,fail
    li s0,0x50000004
    li t6,0x12345555
    .global core_precheck_load
core_precheck_load:
    lw t6,0(s0)
    li t0,0x12345555
    bne t6,t0,fail
    li t0,2
    bne s8,t0,fail
    li t0,1
    bne s9,t0,fail
    li s0,0x400010fc
    li t0,0x600d0011
    .global core_pass_store
core_pass_store:
    sw t0,0(s0)
1:  j 1b
    .align 2
trap_handler:
    csrr t0,mcause
    li t1,0x80000003
    beq t0,t1,msi_handler
    li t1,0x8000000b
    beq t0,t1,mei_handler
    li t1,5
    bne t0,t1,fail
    csrr t2,mepc
    la t1,core_fault_load
    beq t2,t1,first_fault
    la t1,core_precheck_load
    bne t2,t1,fail
    csrr t0,mtval
    li t1,0x50000004
    bne t0,t1,fail
    j finish_fault
first_fault:
    csrr t0,mtval
    li t1,0x50000000
    bne t0,t1,fail
finish_fault:
    addi s8,s8,1
    addi t2,t2,4
    csrw mepc,t2
    mret
msi_handler:
    csrr t2,mepc
    la t1,core_irq_next
    bne t2,t1,fail
    li t1,0x40002000
    sw zero,0(t1)
    addi s7,s7,1
    mret
mei_handler:
    csrr t2,mepc
    la t1,core_precheck_load
    bne t2,t1,fail
    addi s9,s9,1
    mret
fail:
    li s0,0x400010fc
    li t0,0xdead0001
    sw t0,0(s0)
2:  j 2b
