/* Startup-only relocation check; excluded from the DDR-default builds. */
#include "soc.h"

extern uint32_t __tcm_text_start[], __tcm_text_end[], __tcm_text_load[];

int tcm_text_verify(void)
{
    uintptr_t pc;
    __asm__ volatile("auipc %0, 0" : "=r"(pc));
    uart_init(CLK_HZ, BAUD);
    if ((uintptr_t)__tcm_text_start < 0x8000u ||
        (uintptr_t)__tcm_text_end > 0x10000u ||
        pc < (uintptr_t)__tcm_text_start || pc >= (uintptr_t)__tcm_text_end) {
        uart_puts("TCM_TEXT_FAIL range\n");
        return 1;
    }
    volatile const uint32_t *dst = __tcm_text_start;
    volatile const uint32_t *src = __tcm_text_load;
    for (; dst < __tcm_text_end; ++dst, ++src) {
        if (*dst != *src) {
            uart_puts("TCM_TEXT_FAIL copy\n");
            return 2;
        }
    }
    uart_puts("TCM_TEXT start=0x"); uart_puthex((uintptr_t)__tcm_text_start);
    uart_puts(" end=0x"); uart_puthex((uintptr_t)__tcm_text_end);
    uart_puts(" load=0x"); uart_puthex((uintptr_t)__tcm_text_load);
    uart_puts(" pc=0x"); uart_puthex(pc);
    uart_puts(" bytes="); uart_putdec((uintptr_t)__tcm_text_end - (uintptr_t)__tcm_text_start);
    uart_puts(" verify=PASS\n");
    return 0;
}
