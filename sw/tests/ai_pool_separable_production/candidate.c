#define main a97_unused_candidate_main
#include "../../yolo_fixed/main.c"
#undef main
int a96_candidate(const YoloLayer*l,const int8_t*x,int8_t*y,int8_t*s,uint32_t n){(void)s;(void)n;maxpool_layer(l,x,y);return 0;}
unsigned a97_fast(void){return pool_separable_fast_calls;}
unsigned a97_fallback(void){return pool_separable_fallback_calls;}
int8_t *a97_scratch(void){return pool_separable_scratch;}
int a97_raw(const YoloLayer*l,const int8_t*x,int8_t*y,int8_t*s,uint32_t n){return pool_separable(l,x,y,s,n);}
