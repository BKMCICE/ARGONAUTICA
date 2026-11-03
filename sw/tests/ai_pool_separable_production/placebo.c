#define main a97_unused_placebo_main
#include "../../yolo_fixed/main.c"
#undef main
int a96_placebo(const YoloLayer*l,const int8_t*x,int8_t*y){maxpool_layer(l,x,y);return 0;}
