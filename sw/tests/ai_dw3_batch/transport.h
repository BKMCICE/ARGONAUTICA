#ifndef A53_TRANSPORT_H
#define A53_TRANSPORT_H
#include <stdint.h>
#ifdef YOLO_HOST_TEST
uint32_t a53_read(uint32_t);
void a53_write(uint32_t,uint32_t);
#define A53_READ(a) a53_read(a)
#define A53_WRITE(a,v) a53_write(a,v)
#else
#include "soc.h"
#define A53_READ(a) REG32(AI_BASE+(a))
#define A53_WRITE(a,v) (REG32(AI_BASE+(a))=(v))
#endif
#define A53_ID 0x41353331u
/* Error after any start is fatal to this operator. Never recompute a prefix. */
static int a53_wait(void){
    for(unsigned i=0;i<2048;++i){uint32_t s=A53_READ(0x304);
        if(s&4)return -2;
        if(!(s&1))return (s&2)?0:-3;
    }
    return -4;
}
#endif
