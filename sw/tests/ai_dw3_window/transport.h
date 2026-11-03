#ifndef A31_TRANSPORT_H
#define A31_TRANSPORT_H
#include <stdint.h>
#ifdef YOLO_HOST_TEST
uint32_t a31_read(uint32_t);
void a31_write(uint32_t,uint32_t);
void a31_model_reset(unsigned);
extern uint32_t a31_words,a31_slides,a31_stages,a31_seeds,a31_accums;
#define A31_READ(a) a31_read(a)
#define A31_WRITE(a,v) a31_write(a,v)
#else
#include "soc.h"
#define A31_READ(a) REG32(AI_BASE+(a))
#define A31_WRITE(a,v) (REG32(AI_BASE+(a))=(v))
#endif
#endif
