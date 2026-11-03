#include "transport.h"
#define host_dw3_rolling_calls a91_control_host_calls
#define main a91_unused_control_main
#include "../../yolo_fixed/main.c"
#undef main
int a91_control(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*w,const int32_t*p){return conv3x3_rolling(l,x,y,w,p);}
