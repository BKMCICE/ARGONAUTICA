PROG := ai_1x1_small_pack
SRCS := main.c ../../common/tcm_stack.c
TCM_TEXT := 1
STACK_PROBE := 1
STACK_PROBE_BYTES := 8192
STACK_PROBE_ASSERT_SCRIPT := ../../common/stack_probe_tcm_assert.ld
LINK_SCRIPT := ../../common/link_ddr_ai_tcm_stack.ld
CFLAGS += -fno-jump-tables -DYOLO_1X1_SMALL_PACK=1 -DYOLO_REUSE_1X1_WEIGHTS=1
CFLAGS += -DYOLO_1X1_PACK9=1 -DYOLO_1X1_ACC32=1 -DTCM_STACK=1 -DYOLO_REUSE_1X1_INPUT=1 -DYOLO_TILE_1X1_WEIGHTS=1 -DYOLO_PREPACK_1X1_WEIGHTS=1 -DYOLO_1X1_INPUT_BATCH=8
include ../../common/common.mk
