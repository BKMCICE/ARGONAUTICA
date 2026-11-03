#ifndef A74_HOST_MMIO_H
#define A74_HOST_MMIO_H
#include <stdint.h>
uint32_t a74_read(uint32_t);
void a74_write(uint32_t,uint32_t);
#define AI_BLOCK_READ(a) a74_read(a)
#define AI_BLOCK_WRITE(a,v) a74_write(a,v)
#endif
