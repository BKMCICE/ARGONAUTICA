#ifndef A32_HOST_MMIO_H
#define A32_HOST_MMIO_H
#include <stdint.h>
uint32_t a32_read(uint32_t);
void a32_write(uint32_t,uint32_t);
void a32_reset(unsigned);
extern uint32_t a32_starts,a32_weight_words,a32_pixel_words,a32_reads,a32_writes;
extern uint32_t a32_raw_reads,a32_packed_reads,a32_post_writes,a32_post_items;
#define AI_BLOCK_READ(off) a32_read(off)
#define AI_BLOCK_WRITE(off,value) a32_write(off,value)
#endif
