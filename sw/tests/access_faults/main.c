/* Verify machine access-fault causes and mtval for unmapped load/store/fetch. */
#include "soc.h"

static volatile uint32_t load_faults, store_faults, fetch_faults;
static volatile uint32_t bad_cause, bad_mtval;
static volatile uint32_t fetch_resume;
static const uint32_t bad_addr = 0x50000000u;

uint32_t handle_trap(uint32_t mcause, uint32_t mepc, uint32_t mtval)
{
    if (mtval != bad_addr) bad_mtval = mtval ? mtval : 1u;
    switch (mcause) {
    case 5: load_faults++; return mepc + 4;
    case 7: store_faults++; return mepc + 4;
    case 1: fetch_faults++; return fetch_resume;
    default: bad_cause = mcause ? mcause : 0xffffffffu; return mepc + 4;
    }
}

int main(void)
{
    uint32_t value;
    __asm__ volatile("lw %0, 0(%1)" : "=r"(value) : "r"(bad_addr) : "memory");
    __asm__ volatile("sw zero, 0(%0)" :: "r"(bad_addr) : "memory");
    fetch_resume = (uint32_t)&&after_fetch;
    __asm__ goto("jalr zero, 0(%0)" :: "r"(bad_addr) : "memory" : after_fetch);
after_fetch:
    if (load_faults != 1 || store_faults != 1 || fetch_faults != 1 ||
        bad_cause != 0 || bad_mtval != 0) return 1;
    uart_puts("ACCESS_FAULTS PASS\n");
    return 0;
}
