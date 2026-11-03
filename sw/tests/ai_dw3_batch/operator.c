#define main a53_unused_production_main
#include "../../yolo_fixed/main.c"
#undef main
#include "candidate.h"
int a53_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{return conv3x3_rolling(l,x,y,w,p);}
int a53_candidate(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{return a53_batch_operator(l,x,y,w,p);}
