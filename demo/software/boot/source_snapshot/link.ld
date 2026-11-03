/* link.ld - rv_core SoC: 64 KB unified RAM at 0x0.
 * .tohost pinned at 0xF000 (simulator exit); stack grows down from 0xF000.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x10000
}

SECTIONS
{
  .text : {
    KEEP(*(.text.init))
    *(.text .text.*)
    . = ALIGN(4);
  } > RAM

  .rodata : { *(.rodata .rodata.*) *(.srodata .srodata.*) . = ALIGN(4); } > RAM

  .data : {
    __global_pointer$ = . + 0x800;
    *(.data .data.*) *(.sdata .sdata.*)
    . = ALIGN(4);
  } > RAM

  .bss (NOLOAD) : {
    __bss_start = .;
    *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > RAM

  __heap_start = .;
  __stack_top = ORIGIN(RAM) + LENGTH(RAM) - 0x1000;
  ASSERT(__heap_start < __stack_top, "program overlaps reserved stack and tohost area")

  .tohost 0x0000F000 : { KEEP(*(.tohost)) } > RAM
}
