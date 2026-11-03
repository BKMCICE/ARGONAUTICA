#include "transport.h"
#define host_dw3_rolling_calls a90_raw_unused_host_calls
#define main a90_raw_unused_main
#include "../../yolo_fixed/main.c"
#undef main
#include "raw_rolling.h"
int a90_raw(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*k,const int32_t*p){int rc=a90_raw_rolling(l,x,y,k,p);return rc==AI_BLOCK_UNSUPPORTED?conv3x3_rolling(l,x,y,k,p):rc;}
int a90_raw_only(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*k,const int32_t*p){return a90_raw_rolling(l,x,y,k,p);}
