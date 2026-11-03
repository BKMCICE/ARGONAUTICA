#include "transport.h"
#define host_dw3_rolling_calls a86_candidate_unused_host_calls
#define main a86_unused_candidate_main
#include "../../yolo_fixed/main.c"
#undef main
#include "candidate_rolling.h"
int a86_candidate(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*w,const int32_t*p){return a86_candidate_rolling(l,x,y,w,p);}
#ifdef YOLO_HOST_TEST
uint32_t a86_fast_calls(void){return a86_word_batches;}
#endif
