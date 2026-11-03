PROG := ai_pool_cold
SRCS := ../ai_pool_separable_board/main.c ../ai_pool_separable_board/control.c ../ai_pool_separable_board/placebo.c cold_candidate.c ../../common/tcm_stack.c
TCM_TEXT := 1
LINK_SCRIPT := link_cold.ld
CFLAGS += -fno-jump-tables -fno-ipa-icf -DTCM_STACK=1
include ../../common/common.mk
