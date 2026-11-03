/* Actual production operator, no generated substitute. */
#include "../ai_dw3_leaky_clip/transport.h"
#define host_dw3_rolling_calls a92_placebo_host_calls
#define main a92_unused_placebo_main
#include "../../yolo_fixed/main.c"
#undef main
int a91_placebo(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*w,const int32_t*p){return conv3x3_rolling(l,x,y,w,p);}
