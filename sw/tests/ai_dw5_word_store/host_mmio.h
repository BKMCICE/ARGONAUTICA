#ifndef A88_HOST_MMIO_H
#define A88_HOST_MMIO_H
#include <stdint.h>
uint32_t a88_read(uint32_t);
void a88_write(uint32_t,uint32_t);
#define AI_BLOCK_READ(a) a88_read(a)
#define AI_BLOCK_WRITE(a,v) a88_write(a,v)
#endif
