#define main a31_unused_production_main
#include "../../yolo_fixed/main.c"
#undef main
#include "driver.h"
#include "candidate_rolling.h"
int a31_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{return conv3x3_rolling(l,x,y,w,p);}
int a31_candidate(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{return a31_rolling(l,x,y,w,p);}
