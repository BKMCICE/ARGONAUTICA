/* Isolated full-application timing via GNU ld --wrap. No producer edits. */
#include "soc.h"
#define COLD __attribute__((section(".ddr_rgb3"),noinline))
extern int __real_main(void);
extern void __real_yolo_print_detections(const int8_t *,const int8_t *);
static volatile uint64_t post_cycles;
static volatile uint32_t post_calls;
static inline uint64_t sample(void){__asm__ volatile("" ::: "memory");uint64_t v=rdcycle64();__asm__ volatile("" ::: "memory");return v;}
COLD void __wrap_yolo_print_detections(const int8_t *a,const int8_t *b)
{
    uint64_t begin=sample();
    __real_yolo_print_detections(a,b);
    uint64_t end=sample();
    post_cycles=end-begin;
    ++post_calls;
}
COLD static void emit(const char *name,uint64_t value)
{uart_puts(name);uart_puthex((uint32_t)(value>>32));uart_puthex((uint32_t)value);uart_putc('\n');}
COLD int __wrap_main(void)
{
    uint64_t begin=sample();
    int result=__real_main();
    uint64_t end=sample();
    emit("A81_RESPONSE_CYCLES=0x",end-begin);
    emit("A81_POST_CYCLES=0x",post_cycles);
    uart_puts("A81_POST_CALLS=");uart_putdec(post_calls);uart_putc('\n');
    uart_puts(result==0&&post_calls==1?"A81_TIMING_DIAGNOSTIC_PASS\n":"A81_TIMING_DIAGNOSTIC_FAIL\n");
    return result;
}
