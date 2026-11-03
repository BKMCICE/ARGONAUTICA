/* The actual shared production function with the new flag disabled. */
#ifdef YOLO_HOST_TEST
#include "../ai_dw5_post8/host_mmio.h"
#endif
#undef YOLO_DW5_POST8
#define YOLO_DW5_POST8 0
#define host_block_cached_groups a55_control_cached_groups
#define host_block_cached_pixels a55_control_cached_pixels
#define host_dw3_rolling_calls a55_control_dw3_calls
#define main a55_unused_control_main
#include "../../yolo_fixed/main.c"
#undef main
int a55_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{return conv5x5_block(l,x,y,w,p);}
