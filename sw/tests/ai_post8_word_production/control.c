#define host_block_cached_groups a80_control_cached_groups
#define host_block_cached_pixels a80_control_cached_pixels
/* Actual production function; flag is independently selected per translation unit. */
#include "../ai_post8_word_store/host_mmio.h"
#define main a80_control_unused_main
#include "../../yolo_fixed/main.c"
#undef main
int a80_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;return conv1x1_block(l,x,y,w,p,l->ic/l->groups,l->oc/l->groups);}
