PROG := ai_1x1_block
SRCS := main.c
BOARD_DDR ?= 0
ifneq ($(BOARD_DDR),0)
ifneq ($(BOARD_DDR),1)
$(error BOARD_DDR supports only 0 or 1)
endif
endif
ifeq ($(BOARD_DDR),1)
TCM_TEXT := 1
SRCS += ../../common/tcm_stack.c
LINK_SCRIPT := ../../common/link_ddr_ai_tcm_stack.ld
CFLAGS += -DTCM_STACK=1 -DAI_BLOCK_BOARD_DDR=1
endif
include ../../common/common.mk
