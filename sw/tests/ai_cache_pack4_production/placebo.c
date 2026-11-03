#include "../ai_post8_word_store/host_mmio.h"
#define host_block_cached_groups a83_placebo_groups
#define host_block_cached_pixels a83_placebo_pixels
#define main a83_placebo_unused_main
#include "../../yolo_fixed/main.c"
#undef main
int a82_placebo(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*k,const int32_t*p){if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;return conv1x1_block(l,x,y,k,p,l->ic/l->groups,l->oc/l->groups);}
