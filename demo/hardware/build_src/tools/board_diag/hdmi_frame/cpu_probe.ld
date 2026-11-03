OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY { TCM (rwx) : ORIGIN = 0, LENGTH = 0x10000 }
SECTIONS {
  .text : { KEEP(*(.text.init)) *(.text .text.*) . = ALIGN(4); } > TCM
  .rodata : { *(.rodata .rodata.*) *(.srodata .srodata.*) . = ALIGN(4); } > TCM
  .data : { *(.data .data.*) *(.sdata .sdata.*) . = ALIGN(4); } > TCM
  .bss (NOLOAD) : { *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) . = ALIGN(4); } > TCM
  ASSERT(. < 0xf000,"probe overlaps TCM stack")
}
