PROG := shortcut_lut
SRCS := main.c operator.c ../../common/tcm_stack.c
TCM_TEXT := 1
LINK_SCRIPT := ../../common/link_ddr_ai_tcm_stack.ld
A65_FULL ?= 0
ifndef A65_GENERATED
$(error Provide A65_GENERATED pointing to a fresh generate.py output)
endif
CFLAGS += -I$(A65_GENERATED) -DA65_FULL=$(A65_FULL) -DTCM_STACK=1 -fstack-usage
include ../../common/common.mk
