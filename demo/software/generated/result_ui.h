#ifndef H18_RESULT_UI_H
#define H18_RESULT_UI_H
#include <stdint.h>
#define H18_UI_WAIT 0u
#define H18_UI_CAPTURE 1u
#define H18_UI_INFERENCE 2u
#define H18_UI_COMPLETE 3u
#define H18_UI_ERROR 4u
void h18_ui_init(void);
void h18_ui_phase(uint32_t phase);
void h18_ui_detection(uint32_t class_id, uint32_t score_milli);
void h18_ui_cycles(uint64_t cycles);
void h18_ui_failure(uint32_t code);
void h18_ui_ready(void);
int h18_ui_exit(int main_return);
uint32_t h20_ui_complete_ok(void);
#endif
