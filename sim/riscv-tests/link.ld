/* link.ld for running riscv-tests (env/p) on rv_core in simulation.
 * Code starts at the reset PC (0x0). .tohost is pinned at 0xF000 so the
 * testbench can watch a fixed address (tb_core_basic TOHOST_ADDR).
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;
  .text.init : { *(.text.init) }
  . = ALIGN(0x100);
  .text : { *(.text) *(.text.*) }
  . = ALIGN(0x100);
  .data : { *(.data) *(.data.*) *(.sdata) *(.sdata.*) *(.rodata) *(.rodata.*) }
  .bss  : { *(.bss) *(.bss.*) *(.sbss) *(.sbss.*) *(COMMON) }
  . = 0x0000F000;
  .tohost : { *(.tohost) }
  _end = .;
}
