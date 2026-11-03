#define main a97_unused_cold_main
#include "../../yolo_fixed/main.c"
#undef main
#define YOLO_POOL_FUNCTION __attribute__((noinline,section(".ddr_rgb3")))
#include "../../yolo_fixed/pool_separable.h"
__attribute__((noinline)) int a96_candidate(const YoloLayer*l,const int8_t*x,int8_t*y,int8_t*s,uint32_t n){return pool_separable(l,x,y,s,n);}
