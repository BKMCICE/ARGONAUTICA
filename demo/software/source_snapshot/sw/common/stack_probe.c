#include "soc.h"
#include "stack_probe.h"

extern uint32_t __stack_top[], __heap_start[];

/* crt0 scans before this call: this function and its UART helpers are excluded
 * from the snapshot. The painted window covers startup verification + main.
 * Reserved-but-unwritten stack, restored canaries and other inputs may use
 * more stack than this write watermark. It is not a worst-case stack bound. */
void stack_probe_report(uint32_t lowest_changed, uint32_t guard_changed_words,
                        uint32_t snapshot_sp, uint32_t main_return)
{
    uint32_t top = (uintptr_t)__stack_top;
    uart_init(CLK_HZ, BAUD);
    uart_puts("STACK_PROBE start=0x"); uart_puthex(top - STACK_PROBE_BYTES);
    uart_puts(" top=0x"); uart_puthex(top);
    uart_puts(" static_end=0x"); uart_puthex((uintptr_t)__heap_start);
    uart_puts(" lowest_changed=0x"); uart_puthex(lowest_changed);
    uart_puts(" touched_bytes="); uart_putdec(top - lowest_changed);
    uart_puts(" guard_bytes="); uart_putdec(STACK_PROBE_GUARD_BYTES);
    uart_puts(" guard_changed_words="); uart_putdec(guard_changed_words);
    uart_puts(" snapshot_sp=0x"); uart_puthex(snapshot_sp);
    uart_puts(" main_return=0x"); uart_puthex(main_return);
    uart_puts(guard_changed_words ? " guard=FAIL\n" : " guard=PASS\n");
}
