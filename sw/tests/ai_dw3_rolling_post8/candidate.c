#include "transport.h"
#define host_dw3_rolling_calls a89_candidate_unused_host_calls
#define main a89_unused_candidate_main
#include "../../yolo_fixed/main.c"
#undef main
#include "candidate_rolling.h"
int a89_candidate(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*w,const int32_t*p){int rc=a89_post8_rolling(l,x,y,w,p);return rc==AI_BLOCK_UNSUPPORTED?conv3x3_rolling(l,x,y,w,p):rc;}
int a89_candidate_only(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*w,const int32_t*p){return a89_post8_rolling(l,x,y,w,p);}
