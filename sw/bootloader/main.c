/* UART boot protocol: ASCII RV32, little-endian length, FNV-1a checksum,
 * then a flat image linked for 0x8000_0000. Jump after flushing D-cache. */
#include "soc.h"

static uint8_t get_byte(void)
{
    int c;
    do { c = uart_getc_nonblock(); } while (c < 0);
    return (uint8_t)c;
}

static uint32_t get_u32(void)
{
    uint32_t v = 0;
    for (unsigned i = 0; i < 4; i++) v |= (uint32_t)get_byte() << (i * 8);
    return v;
}

int main(void)
{
    uart_init(CLK_HZ, BAUD);
    uart_puts("RV32BOOT1\n");
    for (;;) {
        if (get_byte() != 'R' || get_byte() != 'V' ||
            get_byte() != '3' || get_byte() != '2') continue;
        uint32_t length = get_u32();
        uint32_t expected = get_u32();
        /* Reserve the final 16 KiB of a 16 MiB DDR software window for
         * stack/metadata; model and application images can exceed 64 KiB. */
        if (length == 0 || length > 0x00FFC000u) {
            uart_puts("BAD LENGTH\n");
            continue;
        }
        volatile uint8_t *dst = (volatile uint8_t *)0x80000000u;
        uint32_t hash = 2166136261u;
        for (uint32_t i = 0; i < length; i++) {
            uint8_t b = get_byte();
            dst[i] = b;
            hash = (hash ^ b) * 16777619u;
        }
        if (hash != expected) {
            uart_puts("BAD HASH\n");
            continue;
        }
        __asm__ volatile(".word 0x0000100f" ::: "memory"); /* FENCE.I */
        uart_puts("GO\n");
        ((void (*)(void))0x80000000u)();
    }
}
