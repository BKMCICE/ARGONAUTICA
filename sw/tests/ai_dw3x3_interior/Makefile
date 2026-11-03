PROG := ai_dw3x3_interior
SRCS := main.c ../../common/tcm_stack.c
TCM_TEXT := 1
STACK_PROBE := 1
STACK_PROBE_BYTES := 8192
STACK_PROBE_ASSERT_SCRIPT := ../../common/stack_probe_tcm_assert.ld
LINK_SCRIPT := ../../common/link_ddr_ai_tcm_stack.ld
CFLAGS += -DTCM_STACK=1 -DYOLO_REUSE_DW3X3_WEIGHTS=1 -DYOLO_DW3X3_INTERIOR=1
include ../../common/common.mk
