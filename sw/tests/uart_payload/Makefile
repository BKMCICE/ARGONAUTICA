all: build/payload.bin

build:
	mkdir -p build

build/payload.elf: start.S | build
	riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -Wl,-Ttext=0x80000000 -Wl,-e,_start -o $@ $<

build/payload.bin: build/payload.elf
	riscv-none-elf-objcopy -O binary $< $@

.PHONY: all
