/* Optional YOLO code + 8 KiB stack in upper boot TCM; model/data stay DDR. */
OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY {
  DDR (rwx) : ORIGIN = 0x80000000, LENGTH = 0x01000000
  TCM (rx) : ORIGIN = 0x00008000, LENGTH = 0x00006000
}
SECTIONS {
  .boot : { KEEP(*(.text.init)) . = ALIGN(4); } > DDR
  .text : {
    __tcm_text_start = .;
    *(.text .text.*)
    . = ALIGN(4);
    __tcm_text_end = .;
  } > TCM AT> DDR
  __tcm_text_load = LOADADDR(.text);
  .rodata (LOADADDR(.text) + SIZEOF(.text)) : {
    *(.rodata .rodata.*) *(.srodata .srodata.*) . = ALIGN(4);
  } > DDR
  .data : {
    __global_pointer$ = . + 0x800;
    *(.data .data.*) *(.sdata .sdata.*) . = ALIGN(4);
  } > DDR
  .tohost : { KEEP(*(.tohost)) } > DDR
  .bss (NOLOAD) : {
    __bss_start = .;
    *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) . = ALIGN(4);
    __bss_end = .;
  } > DDR
  __heap_start = .;
  __stack_bottom = 0x0000e000;
  __stack_guard_end = __stack_bottom + 256;
  __stack_top = 0x00010000;
  ASSERT(__tcm_text_end <= __stack_bottom, "TCM code overlaps stack")
  ASSERT(__heap_start < 0x81000000, "AI data exceeds DDR window")
}
