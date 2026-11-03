#ifndef A54_HOST_MMIO_H
#define A54_HOST_MMIO_H
#include <stdint.h>
uint32_t a54_read(uint32_t);
void a54_write(uint32_t,uint32_t);
#define AI_BLOCK_READ(a) a54_read(a)
#define AI_BLOCK_WRITE(a,v) a54_write(a,v)
#endif
