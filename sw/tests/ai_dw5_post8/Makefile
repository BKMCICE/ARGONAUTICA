PROG := ai_dw5_post8
SRCS := main.c operator.c ../../common/tcm_stack.c
TCM_TEXT := 1
LINK_SCRIPT := ../../common/link_ddr_ai_tcm_stack.ld
A54_FULL ?= 0
CFLAGS += -DA54_FULL=$(A54_FULL) -DTCM_STACK=1 -fstack-usage
CFLAGS += -DYOLO_DW5X5_BLOCK=1 -DYOLO_1X1_ACC32=1 -DYOLO_REUSE_1X1_INPUT=1
include ../../common/common.mk
