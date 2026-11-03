PROG := ai_pool_separable_board
SRCS := main.c control.c placebo.c candidate.c ../../common/tcm_stack.c
TCM_TEXT := 1
LINK_SCRIPT := link.ld
CFLAGS += -fno-jump-tables -fno-ipa-icf -DTCM_STACK=1
include ../../common/common.mk
