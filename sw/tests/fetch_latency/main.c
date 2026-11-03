#include "soc.h"

extern const uint32_t fetch_template_start[], fetch_template_end[];
extern char __heap_start[];
typedef uint32_t (*loop_fn)(uint32_t);

#ifndef FETCH_ITERATIONS
#define FETCH_ITERATIONS 20000
#endif
enum { ITERATIONS = FETCH_ITERATIONS, EXPECTED_LOOP_INSTR = 34 * ITERATIONS + 1 };
_Static_assert(ITERATIONS > 0, "fetch loop requires a positive iteration count");

static void field(const char *name, uint32_t value)
{
    uart_puts(name);
    uart_puts("=");
    uart_putdec(value);
    uart_puts(" ");
}

static int measure(const char *location, loop_fn run, unsigned trial)
{
    /* Warm the exact loop, then count only execution and short boundaries.
     * The loop performs no loads/stores; caller/statistics code stays in DDR. */
    uart_puts("FETCH_WARM location="); uart_puts(location); uart_puts("\n");
    if (run(128) != 0) return 1;
    PERF_CTRL = 3;
    CACHE_STATS_CTRL = 3;
    __asm__ volatile("" ::: "memory");
    uint32_t begin = csr_read(mcycle);
    uint32_t result = run(ITERATIONS);
    uint32_t ticks = csr_read(mcycle) - begin;
    __asm__ volatile("" ::: "memory");
    PERF_CTRL = 0;
    CACHE_STATS_CTRL = 0;
    uint32_t cycles = PERF_CYCLES, instr = PERF_INSTR;
    uint32_t istall = PERF_ISTALL, dstall = PERF_DSTALL, traps = PERF_TRAPS;
    uint32_t ihit = CACHE_I_HITS, imiss = CACHE_I_MISSES;

    uart_puts("FETCH_SAMPLE location="); uart_puts(location); uart_puts(" ");
    field("trial", trial); field("iterations", ITERATIONS);
    field("ticks", ticks); field("cycles", cycles); field("instr", instr);
    field("istall", istall); field("dstall", dstall);
    field("ihit", ihit); field("imiss", imiss); field("traps", traps);
    uart_puts("\n");
    return result != 0 || traps != 0 || instr < EXPECTED_LOOP_INSTR ||
           instr > EXPECTED_LOOP_INSTR + 1000 || cycles < instr;
}

int main(void)
{
    uart_init(CLK_HZ, BAUD);
    uart_puts("FETCH_SETUP\n");
    /* This diagnostic reserves these two scratch regions after bootloader
     * handoff. Refuse to overwrite a larger application's own DDR data. */
    if ((uintptr_t)__heap_start >= 0x80008000u) return 1;
    unsigned words = ((uintptr_t)fetch_template_end -
                      (uintptr_t)fetch_template_start) / sizeof(uint32_t);
    if (words != 35) return 2;
    volatile uint32_t *tcm = (volatile uint32_t *)0x00008000u;
    volatile uint32_t *ddr = (volatile uint32_t *)0x80008000u;
    for (unsigned i = 0; i < words; ++i)
        tcm[i] = ddr[i] = fetch_template_start[i];
    uart_puts("FETCH_COPY_OK\n");
    __asm__ volatile(".word 0x0000100f" ::: "memory"); /* FENCE.I */
    uart_puts("FETCH_FENCE_OK\n");
    for (unsigned i = 0; i < words; ++i)
        if (tcm[i] != fetch_template_start[i] || ddr[i] != fetch_template_start[i])
            return 3;
    uart_puts("FETCH_COMPARE_OK\n");

    for (unsigned trial = 1; trial <= 3; ++trial) {
        if (measure("tcm", (loop_fn)0x00008000u, trial) ||
            measure("ddr", (loop_fn)0x80008000u, trial)) {
            uart_puts("FETCH_LATENCY_FAIL\n");
            return 4;
        }
    }
    uart_puts("FETCH_LATENCY_PASS\n");
    return 0;
}
