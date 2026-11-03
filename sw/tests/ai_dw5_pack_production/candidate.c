/* Compile the actual production function with a separate default-off flag. */
#include "../ai_dw5_pack_fast/host_mmio.h"
#define main a75_candidate_unused_main
#include "../../yolo_fixed/main.c"
#undef main
int a74_candidate(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{return conv5x5_block(l,x,y,w,p);}
void a74_pack_candidate(const int8_t *s,uint32_t h,uint32_t w,int32_t y,int32_t x,uint32_t f,uint32_t n,uint32_t p[3])
{dw5_pack_fast(s,h,w,y,x,f,n,p);}
