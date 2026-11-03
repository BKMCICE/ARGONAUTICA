PROG := yolo_layer_selftest
SRCS := main.c ../common/tcm_stack.c
TCM_TEXT := 1
STACK_PROBE := 1
STACK_PROBE_BYTES := 8192
STACK_PROBE_ASSERT_SCRIPT := ../common/stack_probe_tcm_assert.ld
LINK_SCRIPT := ../common/link_ddr_ai_tcm_stack.ld
CFLAGS += -DTCM_STACK=1 -I../yolo_fixed
include ../common/common.mk
