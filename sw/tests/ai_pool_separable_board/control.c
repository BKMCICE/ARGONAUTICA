#define main a96_unused_control_main
#include "../../yolo_fixed/main.c"
#undef main
__attribute__((noinline)) int a96_control(const YoloLayer*l,const int8_t*x,int8_t*y){maxpool_layer(l,x,y);return 0;}
