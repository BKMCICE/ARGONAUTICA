/* soc.h - register map and helpers for the rv_core SoC */
#ifndef SOC_H
#define SOC_H
#include <stdint.h>

#define REG32(a)        (*(volatile uint32_t *)(a))

#define UART_BASE       0x40000000u
#define UART_DATA       REG32(UART_BASE + 0x0)
#define UART_STATUS     REG32(UART_BASE + 0x4)
#define UART_DIV        REG32(UART_BASE + 0x8)
#define UART_IRQ_EN     REG32(UART_BASE + 0xC)
#define UART_ST_TX_FULL  (1u << 0)
#define UART_ST_TX_EMPTY (1u << 1)
#define UART_ST_RX_VALID (1u << 2)

#define GPIO_BASE       0x40001000u
#define GPIO_OUT        REG32(GPIO_BASE + 0x0)
#define GPIO_IN         REG32(GPIO_BASE + 0x4)
#define GPIO_IRQ_EN     REG32(GPIO_BASE + 0x8)
#define GPIO_IRQ_ST     REG32(GPIO_BASE + 0xC)

#define CLINT_BASE      0x40002000u
#define CLINT_MSIP      REG32(CLINT_BASE + 0x00)
#define CLINT_MTIMECMP_LO REG32(CLINT_BASE + 0x08)
#define CLINT_MTIMECMP_HI REG32(CLINT_BASE + 0x0C)
#define CLINT_MTIME_LO  REG32(CLINT_BASE + 0x10)
#define CLINT_MTIME_HI  REG32(CLINT_BASE + 0x14)

#define PERF_BASE       0x40003000u
#define PERF_CTRL       REG32(PERF_BASE + 0x00)
#define PERF_CYCLES     REG32(PERF_BASE + 0x04)
#define PERF_INSTR      REG32(PERF_BASE + 0x08)
#define PERF_BRANCH     REG32(PERF_BASE + 0x0C)
#define PERF_MISPRED    REG32(PERF_BASE + 0x10)
#define PERF_LDUSE      REG32(PERF_BASE + 0x14)
#define PERF_ISTALL     REG32(PERF_BASE + 0x18)
#define PERF_DSTALL     REG32(PERF_BASE + 0x1C)
#define PERF_TRAPS      REG32(PERF_BASE + 0x20)

/* Nine-lane signed INT8 convolution primitive; registers require word writes. */
#define AI_BASE         0x40004000u
#define AI_CTRL         REG32(AI_BASE + 0x00)
#define AI_PIX0         REG32(AI_BASE + 0x04)
#define AI_PIX1         REG32(AI_BASE + 0x08)
#define AI_PIX2         REG32(AI_BASE + 0x0C)
#define AI_WGT0         REG32(AI_BASE + 0x10)
#define AI_WGT1         REG32(AI_BASE + 0x14)
#define AI_WGT2         REG32(AI_BASE + 0x18)
#define AI_BIAS         REG32(AI_BASE + 0x1C)
#define AI_RESULT       REG32(AI_BASE + 0x20)
#define AI_ACCUM        REG32(AI_BASE + 0x24)
#define AI_BUSY         (1u << 0)
#define AI_DONE         (1u << 1)
#define AI_START        (1u << 0)
#define AI_RELU         (1u << 1)
#define AI_CLEAR_DONE   (1u << 2)

#define CACHE_STATS_BASE 0x40005000u
#define CACHE_STATS_CTRL REG32(CACHE_STATS_BASE + 0x00)
#define CACHE_I_HITS     REG32(CACHE_STATS_BASE + 0x04)
#define CACHE_I_MISSES   REG32(CACHE_STATS_BASE + 0x08)
#define CACHE_D_HITS     REG32(CACHE_STATS_BASE + 0x0C)
#define CACHE_D_MISSES   REG32(CACHE_STATS_BASE + 0x10)

/* CSR helpers */
#define csr_read(csr) ({ uint32_t __v; __asm__ volatile("csrr %0, " #csr : "=r"(__v)); __v; })
#define csr_write(csr, v) __asm__ volatile("csrw " #csr ", %0" :: "r"(v))
#define csr_set(csr, v)   __asm__ volatile("csrs " #csr ", %0" :: "r"(v))
#define csr_clear(csr, v) __asm__ volatile("csrc " #csr ", %0" :: "r"(v))

static inline uint64_t rdcycle64(void)
{
    uint32_t hi, lo, hi2;
    do {
        hi  = csr_read(mcycleh);
        lo  = csr_read(mcycle);
        hi2 = csr_read(mcycleh);
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

#define MSTATUS_MIE (1u << 3)
#define MIE_MSIE    (1u << 3)
#define MIE_MTIE    (1u << 7)
#define MIE_MEIE    (1u << 11)

/* uart.c */
void uart_init(uint32_t clk_hz, uint32_t baud);
void uart_putc(char c);
void uart_puts(const char *s);
int  uart_getc_nonblock(void);   /* -1 if none */
void uart_puthex(uint32_t v);
void uart_putdec(uint32_t v);

/* default weak trap handler (crt0 calls handle_trap) */
uint32_t handle_trap(uint32_t mcause, uint32_t mepc, uint32_t mtval);

#endif
