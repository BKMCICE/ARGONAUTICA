/* Large DDR image for the fixed-point YOLO port: code/model in the flat
 * UART boot image, intermediate tensors in NOLOAD BSS. The 16 MiB window is
 * inside the controller's 1 GiB CPU mapping. */
OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY { DDR (rwx) : ORIGIN = 0x80000000, LENGTH = 0x01000000 }
SECTIONS
{
  .text : { KEEP(*(.text.init)) *(.text .text.*) . = ALIGN(4); } > DDR
  .rodata : { *(.rodata .rodata.*) *(.srodata .srodata.*) . = ALIGN(4); } > DDR
  .data : {
    __global_pointer$ = . + 0x800;
    *(.data .data.*) *(.sdata .sdata.*)
    . = ALIGN(4);
  } > DDR
  .tohost : { KEEP(*(.tohost)) } > DDR
  .bss (NOLOAD) : {
    __bss_start = .;
    *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > DDR
  __heap_start = .;
  __stack_top = ORIGIN(DDR) + LENGTH(DDR) - 0x1000;
  ASSERT(__heap_start < __stack_top, "AI image/tensors overlap stack")
}
