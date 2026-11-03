#ifdef YOLO_HOST_TEST
#include "../ai_block8/host_mmio.h"
#endif
#undef YOLO_BLOCK8
#define YOLO_BLOCK8 0
#define host_block_cached_groups a45_control_cached_groups
#define host_block_cached_pixels a45_control_cached_pixels
#define host_dw3_rolling_calls a45_control_dw3_calls
#define main a45_unused_control_main
#include "../../yolo_fixed/main.c"
#undef main
int a33_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *v,const int32_t *p)
{ if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE; return conv1x1_block(l,x,y,v,p,l->ic/l->groups,l->oc/l->groups); }
void *a45_control_scratch(void){return block_input_cache;}
