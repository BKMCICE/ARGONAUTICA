#include "soc.h"
#include "stack_probe.h"

extern uint32_t __stack_bottom[], __stack_guard_end[], __stack_top[], __tcm_text_end[];

int tcm_stack_begin(void)
{
    uintptr_t sp;
    __asm__ volatile("mv %0, sp" : "=r"(sp));
    uart_init(CLK_HZ, BAUD);
    if ((uintptr_t)__stack_bottom != 0xe000u || (uintptr_t)__stack_top != 0x10000u ||
        (uintptr_t)__stack_guard_end != 0xe100u || (uintptr_t)__tcm_text_end > 0xe000u ||
        sp < (uintptr_t)__stack_guard_end || sp >= (uintptr_t)__stack_top) {
        uart_puts("TCM_STACK_FAIL range\n");
        return 4;
    }
    for (volatile uint32_t *p = __stack_bottom; p < __stack_guard_end; ++p)
        *p = (uintptr_t)p ^ STACK_PROBE_PATTERN;
    uart_puts("TCM_STACK begin bottom=0x"); uart_puthex((uintptr_t)__stack_bottom);
    uart_puts(" top=0x"); uart_puthex((uintptr_t)__stack_top);
    uart_puts(" sp=0x"); uart_puthex(sp); uart_puts(" guard_bytes=256\n");
    return 0;
}

int tcm_stack_finish(int main_return)
{
    uintptr_t sp;
    __asm__ volatile("mv %0, sp" : "=r"(sp));
    uint32_t changed = 0;
    for (volatile const uint32_t *p = __stack_bottom; p < __stack_guard_end; ++p)
        if (*p != ((uintptr_t)p ^ STACK_PROBE_PATTERN)) ++changed;
    uart_puts("TCM_STACK finish sp=0x"); uart_puthex(sp);
    uart_puts(" guard_changed_words="); uart_putdec(changed);
    uart_puts(" main_return=0x"); uart_puthex(main_return);
    if (changed || sp < (uintptr_t)__stack_guard_end || sp >= (uintptr_t)__stack_top) {
        uart_puts(" guard=FAIL\nTCM_STACK_FAIL guard\n");
        return 4;
    }
    uart_puts(" guard=PASS\n");
    return main_return;
}
