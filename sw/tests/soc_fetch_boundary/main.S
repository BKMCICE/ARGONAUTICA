.option norvc
.option norelax
.section .tcm,"ax",@progbits
.global _start
_start:
    li sp, 0xff00
    la t0, trap
    csrw mtvec, t0
    li s0, 0
    li s1, 0
    li s2, 0
    li s3, 0
    li s5, 0xe000
    li t1, 1
    sw t1, 0(s5)
    li s4, 32
    la t0, ddr_arithmetic
round_trip:
    jalr ra, t0, 0
    addi s4, s4, -1
    bnez s4, round_trip
    li t1, 32
    bne s0, t1, fail
    bnez s1, fail
    li t1, 2
    sw t1, 0(s5)
    j train_begin

after_redirect:
    li t1, 1
    bne s2, t1, fail
    bne s3, t1, fail
    li t1, 58
    bne a0, t1, fail
    li t1, 3
    sw t1, 0(s5)
    la t0, ddr_smc
    jalr ra, t0, 0
    li t1, 17
    bne a0, t1, fail
    // Warm I-line remains old while a dirty D-line holds the patched instruction.
    li t1, 0x06300513
    sw t1, 0(t0)
    jalr ra, t0, 0
    li t1, 17
    bne a0, t1, fail
    fence.i
    jalr ra, t0, 0
    li t1, 99
    bne a0, t1, fail
    lw t2, 0(t0)
    li t1, 0x06300513
    bne t2, t1, fail
    sw s0, 4(s5)
    sw s1, 8(s5)
    sw s2, 12(s5)
    sw s3, 16(s5)
    sw a0, 20(s5)
    li t1, 4
    sw t1, 0(s5)
    li t0, 0xf000
    li t1, 1
    sw t1, 0(t0)
    j .
fail:
    li t0, 0xf000
    li t1, 3
    sw t1, 0(t0)
    j .
trap:
    li t0, 0xf000
    li t1, 5
    sw t1, 0(t0)
    j .

// Separate fixed sites prevent the training/return branches aliasing cross_jump.
.section .train0,"ax",@progbits
train_begin:
    la t0, ddr_poison
    la ra, train_return
    j cross_jump
.section .train1,"ax",@progbits
train_return:
    // Invalidate I cache but retain the trained JALR predictor entry.
    fence.i
    la t0, tcm_good
    la ra, after_redirect
    j cross_jump
.section .cross_jump,"ax",@progbits
cross_jump:
    jalr zero, t0, 0
.section .tcm_good,"ax",@progbits
tcm_good:
    addi s3, s3, 1
    la t0, ddr_alternate
    jalr ra, t0, 0
    j after_redirect

.section .ddr_arithmetic,"ax",@progbits
ddr_arithmetic:
    addi s0, s0, 1
    xori s1, s1, 0x55
    ret
.section .ddr_smc,"ax",@progbits
ddr_smc:
    addi a0, zero, 17
    ret
.section .ddr_poison,"ax",@progbits
ddr_poison:
    addi s2, s2, 1
    ret
.section .ddr_alternate,"ax",@progbits
ddr_alternate:
    addi a0, zero, 58
    ret
