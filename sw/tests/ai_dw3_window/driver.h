/* Diagnostic only: bounded waits, resident weights, original software Q24.
 * Owns the accelerator; nonzero return invalidates any partially written output.
 * A failed/busy interface must be reset by the owner before another task. */
#ifndef A31_DRIVER_H
#define A31_DRIVER_H
#include "transport.h"
static int a31_fault;
static int32_t a31_wait(void)
{
    if(a31_fault)return 0;
    unsigned n=0;while(!(A31_READ(0)&2u) && ++n<100000u){}
    if(n==100000u){a31_fault=AI_BLOCK_TIMEOUT;return 0;}
    return (int32_t)A31_READ(36);
}
static int32_t a31_seed(uint32_t a,uint32_t b,uint32_t c)
{
    if(a31_fault)return 0;
    A31_WRITE(4,a|(b<<24));A31_WRITE(8,(b>>8)|(c<<16));A31_WRITE(12,c>>16);
    A31_WRITE(0,1);return a31_wait();
}
static uint32_t a31_column(const int8_t *a,const int8_t *b,const int8_t *c,unsigned offset)
{
    return (uint32_t)(uint8_t)a[offset]|(uint32_t)(uint8_t)b[offset]<<8|(uint32_t)(uint8_t)c[offset]<<16;
}
static int32_t a31_submit(const int8_t *a,const int8_t *b,const int8_t *c,unsigned stride)
{
    if(a31_fault)return 0;
    if(stride==2)A31_WRITE(60,a31_column(a,b,c,1));
    A31_WRITE(56,a31_column(a,b,c,2)|(stride==2?0x80000000u:0));return a31_wait();
}
static void a31_load(const int8_t *w,unsigned unused)
{
    (void)unused;
    for(unsigned word=0;word<3;++word){uint32_t v=0;
        for(unsigned b=0;b<4 && word*4+b<9;++b)v|=(uint32_t)(uint8_t)w[word*4+b]<<(b*8);
        A31_WRITE(16+word*4,v);
    }
}
static int32_t a31_boundary(const int8_t *x,uint32_t h,uint32_t w,int32_t y,int32_t col)
{
    uint32_t rows[3]={0,0,0};
    for(unsigned dy=0;dy<3;++dy)for(unsigned dx=0;dx<3;++dx){
        int32_t yy=y+(int32_t)dy,xx=col+(int32_t)dx;
        if(yy>=0 && (uint32_t)yy<h && xx>=0 && (uint32_t)xx<w)
            rows[dy]|=(uint32_t)(uint8_t)x[(uint32_t)yy*w+(uint32_t)xx]<<(dx*8);
    }
    return a31_seed(rows[0],rows[1],rows[2]);
}
#endif
