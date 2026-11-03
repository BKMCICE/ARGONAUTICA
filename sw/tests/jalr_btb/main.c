/* One return-site JALR must learn and correct two alternating call targets. */
#include "soc.h"

__attribute__((noinline)) static uint32_t bump(uint32_t x)
{
    __asm__ volatile("" ::: "memory");
    return x + 1;
}

int main(void)
{
    uint32_t sum = 0;
    for (uint32_t i = 0; i < 32; ++i) {
        sum = bump(sum);
        __asm__ volatile("" ::: "memory");
        sum = bump(sum);
    }
    if (sum != 64) return 1;
    uart_puts("JALR_BTB PASS\n");
    return 0;
}
