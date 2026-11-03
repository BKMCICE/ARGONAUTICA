PROG := fetch_latency
SRCS := main.c loop.S
FETCH_ITERATIONS ?= 20000
CFLAGS += -DFETCH_ITERATIONS=$(FETCH_ITERATIONS)
LINK_SCRIPT := ../../common/link_ddr.ld
include ../../common/common.mk
