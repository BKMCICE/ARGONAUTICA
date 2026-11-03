#include "soc.h"

static volatile uint32_t scratch[32];
static volatile uint32_t traps;
extern char trap_entry;

uint32_t handle_trap(uint32_t cause, uint32_t epc, uint32_t value)
{
    (void)value;
    if (cause == 11) { ++traps; return epc + 4; }
    return epc; /* Unexpected causes are caught by the test timeout. */
}

__attribute__((noinline)) static uint32_t accumulate(uint32_t value)
{
    return value * 17u + 3u;
}

int main(void)
{
    uintptr_t pc;
    __asm__ volatile("auipc %0, 0" : "=r"(pc));
    if (pc < 0x8000u || pc >= 0x10000u ||
        (uintptr_t)&trap_entry < 0x8000u || (uintptr_t)&trap_entry >= 0x10000u ||
        (uintptr_t)scratch < 0x80000000u) return 1;
    for (unsigned i = 0; i < 32; ++i) {
        if (scratch[i]) return 2;
        scratch[i] = accumulate(i);
    }
    for (unsigned i = 0; i < 32; ++i)
        if (scratch[i] != i * 17u + 3u) return 3;
    __asm__ volatile("ecall" ::: "memory");
    if (traps != 1) return 4;
    uart_puts("TCM_EXEC_PASS pc=0x"); uart_puthex(pc); uart_puts("\n");
    return 0;
}
