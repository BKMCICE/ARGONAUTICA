/* POSIX host adapter for executing the exact RV32 layer and decode C code.
 * Only the MMIO dot product is emulated by ai_mac.h; hardware has a separate
 * DDR SoC CPU/MMIO regression. This file is excluded from the RV32 Makefile. */
#include <stdio.h>
#include <stdlib.h>
#include "soc.h"

uint32_t host_ai_calls;
uint32_t host_gpio_out;

void uart_init(uint32_t clock, uint32_t baud) { (void)clock; (void)baud; }
void uart_putc(char value) { putchar(value); }
void uart_puts(const char *value) { fputs(value, stdout); }
int uart_getc_nonblock(void)
{
    int value = getchar();
    if (value == EOF) { fputs("Unexpected image EOF\n", stderr); exit(4); }
    return value;
}
void uart_puthex(uint32_t value) { printf("%08x", value); }
void uart_putdec(uint32_t value) { printf("%u", value); }
