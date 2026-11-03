/* The same production function, sharing validation/upload on new/old hardware. */
#ifdef YOLO_HOST_TEST
#include "../ai_dw5_post8/host_mmio.h"
#endif
#undef YOLO_DW5_POST8
#define YOLO_DW5_POST8 1
#define main a55_unused_candidate_main
#include "../../yolo_fixed/main.c"
#undef main
int a55_candidate(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{return conv5x5_block(l,x,y,w,p);}
