PROG := ai_cached_phase
SRCS := main.c control.c profile.c ../../common/tcm_stack.c
TCM_TEXT := 1
LINK_SCRIPT := ../../common/link_ddr_ai_tcm_stack.ld
A19_SHORT ?= 0
CFLAGS += -DA19_SHORT=$(A19_SHORT) -DTCM_STACK=1 -DYOLO_1X1_BLOCK=1 -DYOLO_BLOCK_INPUT_CACHE=1 -DYOLO_REUSE_1X1_WEIGHTS=1 -DYOLO_PREPACK_1X1_WEIGHTS=1 -DYOLO_TILE_1X1_WEIGHTS=1 -DYOLO_REUSE_1X1_INPUT=1 -DYOLO_1X1_ACC32=1
include ../../common/common.mk
