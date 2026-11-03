#include "soc.h"
extern uint32_t __stack_bottom[], __stack_guard_end[], __stack_top[];

int main(void)
{
    volatile uint32_t values[128];
    if ((uintptr_t)values < (uintptr_t)__stack_guard_end ||
        (uintptr_t)(values+128) > (uintptr_t)__stack_top) return 5;
    for (uint32_t i=0;i<128;++i) values[i]=0x12340000u+i;
    for (uint32_t i=0;i<128;++i) if (values[i]!=0x12340000u+i) return 6;
    uart_puts("TCM_STACK_SELFTEST local=0x"); uart_puthex((uintptr_t)values);
    uart_puts(" PASS\n");
#if PROBE_CASE == 1
    *(volatile uint32_t *)__stack_bottom=0;
#elif PROBE_CASE == 2
    __asm__ volatile(".space 25000"); /* linker-only negative case, never run */
#endif
    return 0;
}
