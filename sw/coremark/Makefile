PROG := coremark
CM   := ../../third_party/coremark
ITERATIONS ?= 1
PROFILE ?= 0
ifeq ($(DDR),1)
LINK_SCRIPT := ../common/link_ddr.ld
ifeq ($(TCM_TEXT),1)
LINK_SCRIPT := ../common/link_ddr_tcm.ld
endif
endif
SRCS := $(CM)/core_main.c $(CM)/core_list_join.c $(CM)/core_matrix.c \
        $(CM)/core_state.c $(CM)/core_util.c core_portme.c ee_printf.c
CFLAGS += -I. -I$(CM) -DITERATIONS=$(ITERATIONS) -DCOREMARK_PROFILE=$(PROFILE) -DPERFORMANCE_RUN=1 \
          -DFLAGS_STR='"$(OPT) -march=$(ARCH)"' -DMAIN_HAS_NOARGC=1 -DMAIN_HAS_NORETURN=0
include ../common/common.mk
