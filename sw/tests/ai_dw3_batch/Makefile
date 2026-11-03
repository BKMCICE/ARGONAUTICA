PROG := ai_dw3_batch
SRCS := main.c operator.c ../../common/tcm_stack.c
TCM_TEXT := 1
LINK_SCRIPT := ../../common/link_ddr_ai_tcm_stack.ld
A53_FULL ?= 0
CFLAGS += -DA53_FULL=$(A53_FULL) -DTCM_STACK=1 -fstack-usage
# The production rolling path's actual dependencies and interior flag.
CFLAGS += -DYOLO_DW3X3_ROLLING=1 -DYOLO_DW3X3_INTERIOR=1 -DYOLO_REUSE_DW3X3_WEIGHTS=1 -DYOLO_1X1_ACC32=1 -DYOLO_REUSE_1X1_INPUT=1
include ../../common/common.mk
