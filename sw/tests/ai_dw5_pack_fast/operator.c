#ifdef YOLO_HOST_TEST
#include "host_mmio.h"
#endif
#define main a74_unused_production_main
#include "../../yolo_fixed/main.c"
#undef main
#include "fast_pack.h"
#include "candidate.inc"
int a74_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{return conv5x5_block(l,x,y,w,p);}
int a74_candidate(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{return a74_fast(l,x,y,w,p);}
#ifdef YOLO_HOST_TEST
void a74_pack_control(const int8_t *s,uint32_t h,uint32_t w,int32_t y,int32_t x,uint32_t f,uint32_t n,uint32_t p[3])
{dw5_pack5(s,h,w,y,x,f,n,p);}
void a74_pack_candidate(const int8_t *s,uint32_t h,uint32_t w,int32_t y,int32_t x,uint32_t f,uint32_t n,uint32_t p[3])
{a74_pack5(s,h,w,y,x,f,n,p);}
#endif
