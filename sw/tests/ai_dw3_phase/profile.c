#include "diag.h"
#ifdef YOLO_HOST_TEST
#include "../ai_1x1_block_layer/host_mmio.h"
#endif
#define host_dw3_rolling_calls a29_unused_host_rolling_calls
#define main a29_unused_profile_main
#include "../../yolo_fixed/main.c"
#undef main
#undef host_dw3_rolling_calls
static A29Stats stats;
static uint32_t sampled;
static inline uint64_t phase_clock(void)
{
#ifdef YOLO_HOST_TEST
    /* Host checks arithmetic and sampling counts, never target timings. */
    static uint64_t tick;return ++tick;
#else
    __asm__ volatile("" ::: "memory");
    uint64_t value=rdcycle64();
    __asm__ volatile("" ::: "memory");return value;
#endif
}
static inline void enter_pixel(void)
{
    sampled=!(stats.interior++&63u);
    stats.samples+=sampled;
}
#include "profile_rolling.h"
int a29_profile(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{
    unsigned char *v=(unsigned char *)&stats;
    for(unsigned i=0;i<sizeof(stats);++i)v[i]=0;
    sampled=0;
    return a29_profile_rolling(l,x,y,w,p);
}
void a29_stats(A29Stats *out){*out=stats;}
uint64_t a29_clock_overhead(void)
{
    uint64_t sum=0;
    for(unsigned i=0;i<1024;++i){uint64_t a=phase_clock();sum+=phase_clock()-a;}
    return sum;
}
