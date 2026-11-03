PROG := tcm_stack_selftest
SRCS := main.c ../common/tcm_stack.c
TCM_TEXT := 1
STACK_PROBE := 1
STACK_PROBE_BYTES := 8192
STACK_PROBE_ASSERT_SCRIPT := ../common/stack_probe_tcm_assert.ld
LINK_SCRIPT := ../common/link_ddr_ai_tcm_stack.ld
PROBE_CASE ?= 0
CFLAGS += -DTCM_STACK=1 -DPROBE_CASE=$(PROBE_CASE)
include ../common/common.mk
