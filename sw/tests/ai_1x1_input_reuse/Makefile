PROG := ai_1x1_input_reuse
SRCS := main.c ../../common/tcm_stack.c
TCM_TEXT := 1
STACK_PROBE := 1
STACK_PROBE_BYTES := 8192
STACK_PROBE_ASSERT_SCRIPT := ../../common/stack_probe_tcm_assert.ld
LINK_SCRIPT := ../../common/link_ddr_ai_tcm_stack.ld
CFLAGS += -DTCM_STACK=1 -DYOLO_REUSE_1X1_INPUT=1 -DYOLO_TILE_1X1_WEIGHTS=1 -DYOLO_PREPACK_1X1_WEIGHTS=1
include ../../common/common.mk
