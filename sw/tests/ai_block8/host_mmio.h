#ifndef A33_HOST_MMIO_H
#define A33_HOST_MMIO_H
#include <stdint.h>
uint32_t a33_read(uint32_t);
void a33_write(uint32_t,uint32_t);
void a33_reset(unsigned);
extern uint32_t a33_starts,a33_weight_words,a33_pixel_words,a33_reads,a33_writes;
extern uint32_t a33_raw_reads;
#define AI_BLOCK_READ(off) a33_read(off)
#define AI_BLOCK_WRITE(off,value) a33_write(off,value)
#endif
