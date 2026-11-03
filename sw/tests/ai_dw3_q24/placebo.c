#ifdef YOLO_HOST_TEST
#include "../ai_1x1_block_layer/host_mmio.h"
#endif
#define host_dw3_rolling_calls a30_placebo_unused_host_calls
#define main a30_unused_placebo_main
#include "../../yolo_fixed/main.c"
#undef main
#undef host_dw3_rolling_calls
#include "placebo_rolling.h"
int a30_placebo(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{
    return a30_placebo_rolling(l,x,y,w,p);
}
