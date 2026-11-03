#ifndef A48_HOST_MMIO_H
#define A48_HOST_MMIO_H
#include <stdint.h>
uint32_t a48_read(uint32_t);
void a48_write(uint32_t,uint32_t);
void a48_reset(unsigned);
extern uint32_t a48_starts,a48_weight_words,a48_pixel_words,a48_reads,a48_writes;
extern uint32_t a48_raw_reads,a48_packed_reads,a48_post_writes,a48_post_items;
#define AI_BLOCK_READ(off) a48_read(off)
#define AI_BLOCK_WRITE(off,value) a48_write(off,value)
#endif
