#include "transport.h"
#define host_dw3_rolling_calls a89_placebo_unused_host_calls
#define main a89_unused_placebo_main
#include "../../yolo_fixed/main.c"
#undef main
#include "placebo_rolling.h"
int a89_placebo(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*w,const int32_t*p){return a89_placebo_rolling(l,x,y,w,p);}
