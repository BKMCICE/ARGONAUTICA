/* DDR upload/bootstrap/data; executable routines run from upper boot TCM. */
OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY {
  DDR (rwx) : ORIGIN = 0x80000000, LENGTH = 0x01000000
  TCM (rx)  : ORIGIN = 0x00008000, LENGTH = 0x00008000
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
    *(.rodata .rodata.*) *(.srodata .srodata.*)
    . = ALIGN(4);
  } > DDR
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
  ASSERT(__heap_start < __stack_top, "AI data overlaps DDR stack")
  ASSERT(__tcm_text_end <= ORIGIN(TCM) + LENGTH(TCM), "Text exceeds reserved TCM")
}
