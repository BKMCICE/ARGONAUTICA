#ifndef H20_HOST_H
#define H20_HOST_H
#include <stdint.h>
#include <stddef.h>
/* Test-only callbacks. Production images compile with H20_HOST_TEST absent. */
uint32_t h20_test_read(uint32_t offset);
void h20_test_write(uint32_t offset,uint32_t value);
uint64_t h20_test_cycles(void);
void h20_test_puts(const char *value);
void h20_test_puthex(uint32_t value);
void h20_test_putdec(uint32_t value);
void h20_test_putc(char value);
void h20_test_raw_byte(char value);
int h20_test_frame_main(void);
int h20_test_stack_finish(int value);
int h20_test_ui_exit(int value);
uint32_t h20_test_ui_ok(void);
void h20_test_ui_failure(uint32_t code);
#define rdcycle64 h20_test_cycles
#define uart_puts h20_test_puts
#define uart_puthex h20_test_puthex
#define uart_putdec h20_test_putdec
#define uart_putc h20_test_putc
#endif
