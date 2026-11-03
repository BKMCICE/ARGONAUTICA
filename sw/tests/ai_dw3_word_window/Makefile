PROG := ai_dw3_word_window
SRCS := main.c control.c placebo.c candidate.c ../../common/tcm_stack.c
TCM_TEXT := 1
LINK_SCRIPT := ../../common/link_ddr_ai_tcm_stack.ld
CFLAGS += -DTCM_STACK=1 -DYOLO_DW3X3_ROLLING=1 -DYOLO_DW3X3_INTERIOR=1 -DYOLO_1X1_SMALL_PACK=1 -DYOLO_REUSE_DW3X3_WEIGHTS=1 -DYOLO_REUSE_1X1_WEIGHTS=1 -DYOLO_1X1_ACC32=1 -DYOLO_REUSE_1X1_INPUT=1 -DYOLO_TILE_1X1_WEIGHTS=1 -DYOLO_PREPACK_1X1_WEIGHTS=1
include ../../common/common.mk
