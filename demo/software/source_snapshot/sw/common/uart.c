/* uart.c - polled UART driver + tiny printf helpers + default trap handler */
#include "soc.h"

void uart_init(uint32_t clk_hz, uint32_t baud)
{
    UART_DIV = clk_hz / baud;
}

void uart_putc(char c)
{
    while (UART_STATUS & UART_ST_TX_FULL) { }
    UART_DATA = (uint32_t)(uint8_t)c;
}

void uart_puts(const char *s)
{
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

int uart_getc_nonblock(void)
{
    uint32_t d = UART_DATA;
    return (d & 0x100u) ? (int)(d & 0xFFu) : -1;
}

void uart_puthex(uint32_t v)
{
    static const char h[] = "0123456789abcdef";
    for (int i = 28; i >= 0; i -= 4) uart_putc(h[(v >> i) & 0xF]);
}

void uart_putdec(uint32_t v)
{
    char buf[11];
    int i = 10;
    buf[i] = 0;
    do { buf[--i] = (char)('0' + v % 10); v /= 10; } while (v);
    uart_puts(&buf[i]);
}

/* Default trap handler: print and halt on exceptions; ignore interrupts.
 * Applications override by defining their own handle_trap. */
__attribute__((weak)) uint32_t handle_trap(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    if (mcause & 0x80000000u) {
        /* interrupt: nothing registered, mask it to avoid a storm */
        csr_clear(mie, 1u << (mcause & 31));
        return mepc;
    }
    uart_puts("\n[TRAP] mcause="); uart_puthex(mcause);
    uart_puts(" mepc=");           uart_puthex(mepc);
    uart_puts(" mtval=");          uart_puthex(mtval);
    uart_puts("\n");
    for (;;) { }
}
