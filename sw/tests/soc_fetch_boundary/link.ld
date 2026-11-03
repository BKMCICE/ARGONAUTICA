OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS {
  .tcm 0x00000000 : { *(.tcm) }
  .train0 0x00001000 : { *(.train0) }
  .train1 0x00001080 : { *(.train1) }
  .cross_jump 0x00001120 : { *(.cross_jump) }
  .tcm_good 0x00002000 : { *(.tcm_good) }
  .ddr_arithmetic 0x80000000 : { *(.ddr_arithmetic) }
  .ddr_smc 0x80001000 : { *(.ddr_smc) }
  .ddr_poison 0x80002000 : { *(.ddr_poison) }
  .ddr_alternate 0x80003000 : { *(.ddr_alternate) }
  /DISCARD/ : { *(.riscv.attributes) *(.comment) *(.eh_frame*) }
}
