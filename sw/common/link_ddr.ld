/* CoreMark executable in cached DDR3 at 0x8000_0000. The bootloader sends
 * the flat binary there, then FENCE.I flushes D-cache and jumps to _start. */
OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY { DDR (rwx) : ORIGIN = 0x80000000, LENGTH = 0x10000 }
SECTIONS
{
  .text : { KEEP(*(.text.init)) *(.text .text.*) . = ALIGN(4); } > DDR
  .rodata : { *(.rodata .rodata.*) *(.srodata .srodata.*) . = ALIGN(4); } > DDR
  .data : {
    __global_pointer$ = . + 0x800;
    *(.data .data.*) *(.sdata .sdata.*)
    . = ALIGN(4);
  } > DDR
  .bss (NOLOAD) : {
    __bss_start = .;
    *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > DDR
  __heap_start = .;
  __stack_top = 0x8000F000;
  ASSERT(__heap_start < __stack_top, "DDR program overlaps stack and tohost")
  .tohost 0x8000F000 : { KEEP(*(.tohost)) } > DDR
}
