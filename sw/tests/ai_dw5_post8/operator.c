#ifdef YOLO_HOST_TEST
#include "host_mmio.h"
#endif
#define main a54_unused_production_main
#include "../../yolo_fixed/main.c"
#undef main
#include "candidate.inc"
int a54_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{return conv5x5_block(l,x,y,w,p);}
int a54_candidate(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{return a54_post8(l,x,y,w,p);}
