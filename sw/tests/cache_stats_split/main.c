/* CPU/cache/MMIO regression; TCM program, real cached DDR transactions. */
#include "soc.h"

static volatile uint32_t sink;
static void drain(void) { __asm__ volatile(".rept 8\nnop\n.endr" ::: "memory"); }
static void traffic(void)
{
    volatile uint32_t *p = (volatile uint32_t *)0x80000000u;
    for (unsigned i = 0; i < 24; ++i) {
        p[i * 512] = 0x12345600u + i;
        sink ^= p[i * 512]; /* hit before later conflict evictions */
    }
    for (unsigned i = 0; i < 24; ++i) sink ^= p[i * 512];
    __asm__ volatile(".word 0x0000100f" ::: "memory"); /* FENCE.I */
}
static int zero(void)
{
    return CACHE_I_HITS == 0 && CACHE_I_MISSES == 0 &&
           CACHE_D_HITS == 0 && CACHE_D_MISSES == 0;
}
int main(void)
{
    CACHE_STATS_CTRL = 2; /* clear + disable */
    drain();
    if (CACHE_STATS_CTRL != 0 || !zero()) return 1;
    traffic();
    if (!zero()) return 2;
    CACHE_STATS_CTRL = 1;
    traffic();
    CACHE_STATS_CTRL = 0;
    drain();
    uint32_t a=CACHE_I_HITS,b=CACHE_I_MISSES,c=CACHE_D_HITS,d=CACHE_D_MISSES;
    if (c == 0 || d == 0) return 3;
    traffic();
    if (a!=CACHE_I_HITS || b!=CACHE_I_MISSES || c!=CACHE_D_HITS || d!=CACHE_D_MISSES) return 4;
    /* Preserve the original address aliases and ignored byte-enable policy. */
    *(volatile uint8_t *)(CACHE_STATS_BASE + 0x20u) = 2;
    drain();
    if (CACHE_STATS_CTRL != 0 || !zero()) return 5;
    CACHE_STATS_CTRL=3; CACHE_STATS_CTRL=0; CACHE_STATS_CTRL=3;
    drain();
    if (CACHE_STATS_CTRL != 1 || !zero()) return 6;
    traffic();
    CACHE_STATS_CTRL=0;
    drain();
    if (CACHE_D_HITS == 0 || CACHE_D_MISSES == 0) return 7;
    CACHE_STATS_CTRL=2; CACHE_STATS_CTRL=2;
    drain();
    return zero() ? 0 : 8;
}
