PROG := ai_dw3_phase
SRCS := main.c control.c profile.c ../../common/tcm_stack.c
TCM_TEXT := 1
LINK_SCRIPT := ../../common/link_ddr_ai_tcm_stack.ld
A29_SHORT ?= 0
CFLAGS += -DA29_SHORT=$(A29_SHORT) -DTCM_STACK=1 -DYOLO_DW3X3_ROLLING=1 -DYOLO_REUSE_DW3X3_WEIGHTS=1 -DYOLO_REUSE_1X1_WEIGHTS=1 -DYOLO_1X1_ACC32=1 -DYOLO_REUSE_1X1_INPUT=1 -DYOLO_TILE_1X1_WEIGHTS=1 -DYOLO_PREPACK_1X1_WEIGHTS=1
include ../../common/common.mk
