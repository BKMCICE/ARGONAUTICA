#define main a96_unused_candidate_main
#include "../../yolo_fixed/main.c"
#undef main
#include "../ai_pool_separable/prototype.h"
__attribute__((noinline)) int a96_candidate(const YoloLayer*l,const int8_t*x,int8_t*y,int8_t*s,uint32_t n){return a93_pool(l,x,y,s,n);}
