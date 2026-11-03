/* Capture candidate only: keep existing A25 TCM layout, reserve frame/CHW.
 * No production linker is edited. Runtime heap must honor __heap_limit. */
OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY {
  DDR (rwx) : ORIGIN = 0x80000000, LENGTH = 0x00400000
  TCM (rx) : ORIGIN = 0x00008000, LENGTH = 0x00006000
}
SECTIONS {
  .boot : { KEEP(*(.text.init)) . = ALIGN(4); } > DDR
  .text : {
    __tcm_text_start = .; *(.text .text.*) . = ALIGN(4); __tcm_text_end = .;
  } > TCM AT> DDR
  __tcm_text_load = LOADADDR(.text);
  .ddr_rgb3 (LOADADDR(.text) + SIZEOF(.text)) : { *(.ddr_rgb3) . = ALIGN(4); } > DDR
  .ddr_h07 : { *(.ddr_h07 .ddr_h07.*) . = ALIGN(4); } > DDR
  .rodata : { *(.rodata .rodata.*) *(.srodata .srodata.*) . = ALIGN(4); } > DDR
  .data : {
    __global_pointer$ = . + 0x800; *(.data .data.*) *(.sdata .sdata.*) . = ALIGN(4);
  } > DDR
  .tohost : { KEEP(*(.tohost)) } > DDR
  .bss (NOLOAD) : {
    __bss_start = .;
    . = ALIGN(32);
    __h07_guard_low = .; KEEP(*(.h07_chw_guard_low))
    __h07_input_start = .; KEEP(*(.h07_chw)) __h07_input_end = .;
    __h07_guard_high = .; KEEP(*(.h07_chw_guard_high))
 *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) . = ALIGN(4); __bss_end = .;
  } > DDR
  __heap_start = .;
  __heap_limit = ORIGIN(DDR) + LENGTH(DDR);
  __stack_bottom = 0x0000e000;
  __stack_guard_end = __stack_bottom + 256;
  __stack_top = 0x00010000;
  __capture_frame_start = 0x80400000;
  __capture_frame_limit = 0x80a00000;
  ASSERT(__h07_input_start == __h07_guard_low + 32,"H07 lower input guard")
  ASSERT(__h07_input_end == __h07_input_start + 307200,"H07 CHW exact length")
  ASSERT(__h07_guard_high == __h07_input_end,"H07 upper input guard")
  ASSERT(__h07_guard_high + 32 <= 0x80400000,"H07 input below RAW protection")
  ASSERT(__tcm_text_end <= __stack_bottom,"TCM code overlaps stack")
  ASSERT(__heap_start < __heap_limit,"application exceeds capture boundary")
  ASSERT(__capture_frame_start == 0x80400000 && __capture_frame_limit == 0x80a00000,"frame reserve differs")
}
