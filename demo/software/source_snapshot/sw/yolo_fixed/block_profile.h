/* Optional target-only task sampling. Counter storage is static DDR, not stack.
 * Intervals use unsigned mcycle-low differences; each timed task must finish in
 * less than 2^32 cycles. Reports retain raw instrumentation cost, never subtract
 * empty-CSR calibration as though it recovered an uninstrumented runtime.
 */
#ifndef YOLO_BLOCK_PROFILE_H
#define YOLO_BLOCK_PROFILE_H
enum { BP_SETUP, BP_PACK, BP_WRITE, BP_WAIT, BP_READ, BP_Q24, BP_PHASES };
typedef struct {
    uint64_t phase[BP_PHASES];
    uint64_t weight_cycles, task_cycles, engine_cycles;
#if YOLO_BLOCK_CACHE_PHASE_PROFILE
    uint64_t cache_cycles;
#endif
    uint32_t tasks, samples, batches, weight_words;
    uint32_t vectors, input_words, result_words, polls, dots, max_task;
} BlockPhaseStat;
static BlockPhaseStat block_phase_stats[YOLO_LAYER_COUNT];
static uint32_t block_phase_index, block_clock_min, block_clock_max;
static inline uint32_t block_phase_clock(void)
{
    uint32_t value;
    __asm__ volatile("csrr %0, mcycle" : "=r"(value) :: "memory");
    return value;
}
static void block_phase_calibrate(void)
{
    block_clock_min = UINT32_MAX;
    for (uint32_t i = 0; i < 64u; ++i) {
        uint32_t start = block_phase_clock();
        uint32_t delta = block_phase_clock() - start;
        if (delta < block_clock_min) block_clock_min = delta;
        if (delta > block_clock_max) block_clock_max = delta;
    }
}
static void block_phase_field(const char *name, uint64_t value)
{
    uart_puts(name); uart_puts("=0x");
    uart_puthex((uint32_t)(value >> 32)); uart_puthex((uint32_t)value);
}
static void print_block_phase_profile(void)
{
    uart_puts("YOLO_BLOCK_PHASE_BEGIN stride=64 tail=group_last clock_bits=32 calibration_min=");
    uart_putdec(block_clock_min); uart_puts(" calibration_max=");
    uart_putdec(block_clock_max); uart_putc('\n');
    for (uint32_t i = 0; i < YOLO_LAYER_COUNT; ++i) {
        const BlockPhaseStat *s = &block_phase_stats[i];
        if (!s->tasks) continue;
        uart_puts("YOLO_BLOCK_PHASE index="); uart_putdec(i);
        uart_puts(" tasks="); uart_putdec(s->tasks);
        uart_puts(" samples="); uart_putdec(s->samples);
        uart_puts(" batches="); uart_putdec(s->batches);
        uart_puts(" wwords="); uart_putdec(s->weight_words);
        uart_puts(" vectors="); uart_putdec(s->vectors);
        uart_puts(" iwords="); uart_putdec(s->input_words);
        uart_puts(" rwords="); uart_putdec(s->result_words);
        uart_puts(" polls="); uart_putdec(s->polls);
        uart_puts(" dots="); uart_putdec(s->dots);
        uart_puts(" max_task="); uart_putdec(s->max_task);
#if YOLO_BLOCK_CACHE_PHASE_PROFILE
        block_phase_field(" cache", s->cache_cycles);
#endif
        block_phase_field(" weight", s->weight_cycles);
        block_phase_field(" setup", s->phase[BP_SETUP]);
        block_phase_field(" pack", s->phase[BP_PACK]);
        block_phase_field(" write", s->phase[BP_WRITE]);
        block_phase_field(" wait", s->phase[BP_WAIT]);
        block_phase_field(" read", s->phase[BP_READ]);
        block_phase_field(" q24", s->phase[BP_Q24]);
        block_phase_field(" task", s->task_cycles);
        block_phase_field(" engine", s->engine_cycles); uart_putc('\n');
    }
    uart_puts("YOLO_BLOCK_PHASE_END\n");
}
#define BLOCK_PHASE_BEGIN() do { if (phase_sample) phase_start = block_phase_clock(); } while (0)
#define BLOCK_PHASE_END(which) do { if (phase_sample) { \
    uint32_t phase_end = block_phase_clock(); \
    phase_stat->phase[(which)] += (uint32_t)(phase_end - phase_start); \
} } while (0)
#endif
