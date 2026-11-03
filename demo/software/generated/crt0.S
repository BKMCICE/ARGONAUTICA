/* crt0.S - reset entry for rv_core bare-metal programs.
 * Sets up sp/gp, clears .bss, copies .data if needed (not needed: RAM image),
 * installs the trap vector, calls main, then parks writing exit code to
 * the simulator tohost address (harmless on hardware).
 */
    .section .text.init, "ax"
    .globl _start
_start:
    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop
    la   sp, __stack_top
#if TCM_TEXT
    /* Flat payload is still uploaded to DDR. Copy only executable text to
     * the reserved upper 32 KiB of boot TCM before entering that code. */
    la   t0, __tcm_text_load
    la   t1, __tcm_text_start
    la   t2, __tcm_text_end
5:  bgeu t1, t2, 6f
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    5b
6:  .word 0x0000100f          /* FENCE.I; encoding avoids an ISA flag change */
#endif
    la   t0, trap_entry
    csrw mtvec, t0
    /* clear bss */
    la   t0, __bss_start
    la   t1, __bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:
#if STACK_PROBE
#include "stack_probe.h"
    /* No C call/stack stores before painting. Keep clear of the static image;
     * the optional linker assertion checks the entire fixed window. */
    la   t1, __stack_top
    li   t2, STACK_PROBE_BYTES
    sub  t0, t1, t2
    li   t3, STACK_PROBE_PATTERN
.Lstack_probe_paint:
    xor  t4, t0, t3
    sw   t4, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, .Lstack_probe_paint
#endif
#if TCM_STACK
    call tcm_stack_begin
    bnez a0, 4f
#endif
#if TCM_TEXT
    call tcm_text_verify
    bnez a0, 4f
#endif
    /* H20 DDR wrapper owns each frame stack check and final publication. */
    call h20_loop_entry
#if STACK_PROBE
    /* Snapshot after main returns, before the reporter can touch the stack.
     * A word-address XOR pattern makes the expected value position-specific.
     * a0=lowest changed address; a1=changed words in the bottom guard. */
    mv   s0, a0
    la   t1, __stack_top
    li   t2, STACK_PROBE_BYTES
    sub  t0, t1, t2
    li   t2, STACK_PROBE_GUARD_BYTES
    add  t2, t0, t2
    li   t3, STACK_PROBE_PATTERN
    mv   a0, t1
    li   a1, 0
.Lstack_probe_scan:
    xor  t4, t0, t3
    lw   t5, 0(t0)
    beq  t4, t5, .Lstack_probe_next
    bne  a0, t1, .Lstack_probe_guard
    mv   a0, t0
.Lstack_probe_guard:
    bgeu t0, t2, .Lstack_probe_next
    addi a1, a1, 1
.Lstack_probe_next:
    addi t0, t0, 4
    bltu t0, t1, .Lstack_probe_scan
    mv   a2, sp
    mv   a3, s0
    call stack_probe_report
    mv   a0, s0
#endif
    /* exit: tohost = (code << 1) | 1 */
4:  slli a0, a0, 1
    ori  a0, a0, 1
    la   t0, tohost
    sw   a0, 0(t0)
3:  j    3b

/* ---- trap entry: save caller-saved regs, call handle_trap(mcause, mepc, mtval) ---- */
#if TCM_TEXT
    .section .text.trap, "ax"
#endif
    .align 4
    .globl trap_entry
trap_entry:
    addi sp, sp, -64
    sw   ra,  0(sp)
    sw   t0,  4(sp)
    sw   t1,  8(sp)
    sw   t2, 12(sp)
    sw   a0, 16(sp)
    sw   a1, 20(sp)
    sw   a2, 24(sp)
    sw   a3, 28(sp)
    sw   a4, 32(sp)
    sw   a5, 36(sp)
    sw   a6, 40(sp)
    sw   a7, 44(sp)
    sw   t3, 48(sp)
    sw   t4, 52(sp)
    sw   t5, 56(sp)
    sw   t6, 60(sp)
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    call handle_trap
    csrw mepc, a0          /* handler returns (possibly advanced) mepc */
    lw   ra,  0(sp)
    lw   t0,  4(sp)
    lw   t1,  8(sp)
    lw   t2, 12(sp)
    lw   a0, 16(sp)
    lw   a1, 20(sp)
    lw   a2, 24(sp)
    lw   a3, 28(sp)
    lw   a4, 32(sp)
    lw   a5, 36(sp)
    lw   a6, 40(sp)
    lw   a7, 44(sp)
    lw   t3, 48(sp)
    lw   t4, 52(sp)
    lw   t5, 56(sp)
    lw   t6, 60(sp)
    addi sp, sp, 64
    mret

    .section .tohost, "aw", @progbits
    .align 4
    .globl tohost
tohost: .word 0
    .globl fromhost
fromhost: .word 0
