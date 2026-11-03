#ifndef A79_HOST_MMIO_H
#define A79_HOST_MMIO_H
#include <stdint.h>
uint32_t a79_read(uint32_t);
void a79_write(uint32_t,uint32_t);
#define AI_BLOCK_READ(a) a79_read(a)
#define AI_BLOCK_WRITE(a,v) a79_write(a,v)
#endif
