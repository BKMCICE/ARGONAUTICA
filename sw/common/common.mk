# common.mk - shared build rules for rv_core bare-metal programs.
# A program Makefile sets PROG and SRCS (relative to its dir) and includes this.
#   make            -> build/<PROG>.elf/.bin/.hex/.lst
#   make sim        -> run in iverilog on soc_top (sim/tb/tb_soc.v)
#   make ARCH=rv32i -> disable M extension (default rv32im)
SW_ROOT   := $(dir $(lastword $(MAKEFILE_LIST)))
ROOT      := $(abspath $(SW_ROOT)/../..)
COMMON    := $(abspath $(SW_ROOT))
LINK_SCRIPT ?= $(COMMON)/link.ld
BUILD     ?= build

RISCV_PREFIX ?= riscv-none-elf-
CC      := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
OBJDUMP := $(RISCV_PREFIX)objdump
PYTHON  ?= python

ARCH    ?= rv32im
ABI     := ilp32
OPT     ?= -O2
CLK_HZ  ?= 100000000
BAUD    ?= 115200
ENABLE_BTB ?= 0

CFLAGS  += -march=$(ARCH)_zicsr -mabi=$(ABI) $(OPT) -g \
           -ffreestanding -fno-builtin -nostdlib -nostartfiles \
           -Wall -Wextra -I$(COMMON) -DCLK_HZ=$(CLK_HZ) -DBAUD=$(BAUD) \
           -fno-common -ffunction-sections -fdata-sections
LDFLAGS += -march=$(ARCH)_zicsr -mabi=$(ABI) -nostdlib -nostartfiles \
           -Wl,--gc-sections -T $(LINK_SCRIPT)
# libgcc: GNU ld cannot open non-ASCII paths, so build the path from the
# ASCII junction (RISCV_HOME, set by tools/env.ps1) instead of asking gcc.
RISCV_HOME ?= F:/rvtools/xpack-riscv-none-elf-gcc-15.2.0-1
GCC_VER    := $(shell $(CC) -dumpversion)
MULTI_DIR  := $(shell $(CC) -march=$(ARCH)_zicsr -mabi=$(ABI) -print-multi-directory)
LDLIBS  += $(RISCV_HOME)/lib/gcc/riscv-none-elf/$(GCC_VER)/$(MULTI_DIR)/libgcc.a

TCM_TEXT ?= 0
COMMON_SRCS := $(COMMON)/crt0.S $(COMMON)/uart.c
ifeq ($(TCM_TEXT),1)
CFLAGS += -DTCM_TEXT=1
COMMON_SRCS += $(COMMON)/tcm_text.c
endif
ALL_SRCS    := $(COMMON_SRCS) $(SRCS)

# A bounded write-watermark diagnostic, completely absent when disabled.
STACK_PROBE ?= 0
STACK_PROBE_BYTES ?= 65536
STACK_PROBE_GUARD_BYTES ?= 256
STACK_PROBE_ASSERT_SCRIPT ?= $(COMMON)/stack_probe_assert.ld
ifeq ($(STACK_PROBE),1)
CFLAGS += -DSTACK_PROBE=1 -DSTACK_PROBE_BYTES=$(STACK_PROBE_BYTES) \
          -DSTACK_PROBE_GUARD_BYTES=$(STACK_PROBE_GUARD_BYTES)
LDFLAGS += -Wl,--defsym=__stack_probe_bytes=$(STACK_PROBE_BYTES) \
           -Wl,-T,$(STACK_PROBE_ASSERT_SCRIPT)
ALL_SRCS += $(COMMON)/stack_probe.c
endif

ELF := $(BUILD)/$(PROG).elf
BIN := $(BUILD)/$(PROG).bin
HEX := $(BUILD)/$(PROG).hex
LST := $(BUILD)/$(PROG).lst

.PHONY: all clean sim size FORCE
all: $(HEX) $(LST) size

$(BUILD):
	mkdir -p $(BUILD)

# Command-line ARCH/BAUD/CLK_HZ/ITERATIONS are not file prerequisites.
# Rebuild the small bare-metal image so changing one cannot reuse a stale ELF.
FORCE:

$(ELF): $(ALL_SRCS) $(LINK_SCRIPT) $(COMMON)/soc.h FORCE | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(ALL_SRCS) $(LDLIBS)

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(HEX): $(BIN)
	$(PYTHON) $(ROOT)/tools/bin2hex.py $< $@ --pad-words 16384

$(LST): $(ELF)
	$(OBJDUMP) -d -S $< > $@

size: $(ELF)
	$(RISCV_PREFIX)size $<

# Run the simulation from the repo root with relative paths: vvp/$readmemh
# cannot open absolute paths that contain non-ASCII characters.
PROG_DIR := $(patsubst $(ROOT)/%,%,$(abspath .))
SIM_ARGS ?=
sim: $(HEX)
	cd $(ROOT) && iverilog -g2012 -Ptb_soc.CLK_HZ=$(CLK_HZ) -Ptb_soc.BAUD=$(BAUD) -Ptb_soc.ENABLE_BTB=$(ENABLE_BTB) -o $(PROG_DIR)/$(BUILD)/tb_soc.vvp -I rtl/core sim/tb/tb_soc.v rtl/core/*.v rtl/bus/*.v rtl/mem/*.v rtl/periph/*.v rtl/top/soc_top.v
	cd $(ROOT) && vvp $(PROG_DIR)/$(BUILD)/tb_soc.vvp +hex=$(PROG_DIR)/$(HEX) $(SIM_ARGS)

clean:
	rm -rf $(BUILD)
