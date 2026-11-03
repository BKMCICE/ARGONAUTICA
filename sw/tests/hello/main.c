/* hello - first program: UART banner, GPIO, timer interrupt, perf counters. */
#include "soc.h"

static volatile uint32_t ticks;

uint32_t handle_trap(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    if (mcause == 0x80000007u) {           /* machine timer interrupt */
        ticks++;
        uint64_t now = ((uint64_t)CLINT_MTIME_HI << 32) | CLINT_MTIME_LO;
        now += CLK_HZ / 1000;              /* 1 ms */
        CLINT_MTIMECMP_HI = 0xFFFFFFFFu;   /* avoid spurious match while updating */
        CLINT_MTIMECMP_LO = (uint32_t)now;
        CLINT_MTIMECMP_HI = (uint32_t)(now >> 32);
        return mepc;
    }
    if (mcause == 11) {                    /* ecall from M: just skip it */
        return mepc + 4;
    }
    uart_puts("\n[TRAP] mcause="); uart_puthex(mcause);
    uart_puts(" mepc="); uart_puthex(mepc);
    uart_puts(" mtval="); uart_puthex(mtval); uart_puts("\n");
    for (;;) { }
}

static uint32_t fib(uint32_t n)
{
    uint32_t a = 0, b = 1;
    while (n--) { uint32_t t = a + b; a = b; b = t; }
    return a;
}

int main(void)
{
    uart_init(CLK_HZ, BAUD);
    uart_puts("\nrv_core SoC on Pangu 50K (PGL50H)\n");
    uart_puts("misa=");   uart_puthex(csr_read(misa));
    uart_puts(" hart=");  uart_putdec(csr_read(mhartid));
    uart_puts("\n");

    /* timer interrupt every 1 ms */
    CLINT_MTIMECMP_LO = CLK_HZ / 1000;
    CLINT_MTIMECMP_HI = 0;
    csr_set(mie, MIE_MTIE);
    csr_set(mstatus, MSTATUS_MIE);

    /* ecall exercise */
    __asm__ volatile("ecall");

    PERF_CTRL = 0x3;                       /* clear + enable */
    uint32_t t0 = csr_read(mcycle);
    uint32_t f = fib(30);
    uint32_t t1 = csr_read(mcycle);
    PERF_CTRL = 0x0;

    uart_puts("fib(30)="); uart_putdec(f);
    uart_puts(" cycles="); uart_putdec(t1 - t0);
    uart_puts(" instr=");  uart_putdec(PERF_INSTR);
    uart_puts(" br=");     uart_putdec(PERF_BRANCH);
    uart_puts(" mispred=");uart_putdec(PERF_MISPRED);
    uart_puts(" lduse=");  uart_putdec(PERF_LDUSE);
    uart_puts(" dstall="); uart_putdec(PERF_DSTALL);
    uart_puts("\n");

#if __riscv_mul
    uint32_t m = 123456789u * 7u, d = 123456789u / 7u, r = 123456789u % 7u;
    uart_puts("mul/div: "); uart_putdec(m); uart_putc(' ');
    uart_putdec(d); uart_putc(' '); uart_putdec(r); uart_puts("\n");
#endif

    /* wait for a few timer ticks, blink LEDs */
    while (ticks < 5) { GPIO_OUT = ticks; }
    uart_puts("ticks="); uart_putdec(ticks); uart_puts(" keys="); uart_puthex(GPIO_IN);
    uart_puts("\nDONE\n");
    return 0;
}
