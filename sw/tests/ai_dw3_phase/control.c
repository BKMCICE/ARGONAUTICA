#ifdef YOLO_HOST_TEST
#include "../ai_1x1_block_layer/host_mmio.h"
#endif
#define main a29_unused_control_main
#include "../../yolo_fixed/main.c"
#undef main
int a29_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{
    return conv3x3_rolling(l,x,y,w,p);
}
