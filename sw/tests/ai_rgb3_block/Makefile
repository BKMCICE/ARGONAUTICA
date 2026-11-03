PROG := ai_rgb3_block
SRCS := main.c ../../common/tcm_stack.c
TCM_TEXT := 1
LINK_SCRIPT := ../../common/link_ddr_ai_tcm_stack.ld
A24_SHORT ?= 0
CFLAGS += -DA24_SHORT=$(A24_SHORT) -DTCM_STACK=1 -DYOLO_3X3_INPUT3_PREPACK=1 -DYOLO_REUSE_DW3X3_WEIGHTS=1 -DYOLO_TILE_1X1_WEIGHTS=1
RGB3_PRODUCTION ?= 0
ifeq ($(RGB3_PRODUCTION),1)
SRCS := production_operator.c ../../common/tcm_stack.c
LINK_SCRIPT := ../../common/link_ddr_ai_tcm_stack_rgb3.ld
CFLAGS += -DYOLO_RGB3_BLOCK=1 -DYOLO_1X1_ACC32=1 -DYOLO_REUSE_1X1_INPUT=1
endif
include ../../common/common.mk
