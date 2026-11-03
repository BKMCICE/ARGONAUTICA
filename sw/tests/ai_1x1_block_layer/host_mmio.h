#ifndef A03_HOST_MMIO_H
#define A03_HOST_MMIO_H
#ifndef __ASSEMBLER__
#include <stdint.h>
uint32_t a03_read(uint32_t offset);
void a03_write(uint32_t offset, uint32_t value);
void a03_reset(unsigned mode);
extern uint32_t a03_starts, a03_weight_words, a03_pixel_words, a03_reads, a03_writes;
#define AI_BLOCK_READ(off) a03_read(off)
#define AI_BLOCK_WRITE(off,value) a03_write(off,value)
#endif
#endif
