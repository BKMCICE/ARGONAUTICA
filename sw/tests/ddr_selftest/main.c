/* Runs from boot TCM and exercises the cached DDR3 window. */
#include "soc.h"

int main(void)
{
    volatile uint32_t *const ddr = (volatile uint32_t *)0x80000000u;
    ddr[0] = 0x13579BDFu;
    ddr[0x800 / 4] = 0x02468ACEu;
    ddr[0x1000 / 4] = 0xDEADBEEFu;
    if (ddr[0] != 0x13579BDFu) return 1;
    if (ddr[0x800 / 4] != 0x02468ACEu) return 2;
    if (ddr[0x1000 / 4] != 0xDEADBEEFu) return 3;
    ((volatile uint8_t *)ddr)[1] = 0xA5;
    if (ddr[0] != 0x1357A5DFu) return 4;
    __asm__ volatile(".word 0x0000100f" ::: "memory"); /* FENCE.I: flush D and invalidate I */
    if (ddr[0] != 0x1357A5DFu) return 5;
    if (CACHE_D_HITS == 0 || CACHE_D_MISSES == 0) return 6;
    return 0;
}
