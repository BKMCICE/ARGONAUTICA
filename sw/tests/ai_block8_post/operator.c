#ifdef YOLO_HOST_TEST
#include "host_mmio.h"
#endif
#define main a48_unused_production_main
#include "../../yolo_fixed/main.c"
#undef main
#include "candidate_block.h"
int a48_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{
    if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;
    return conv1x1_block(l,x,y,w,p,l->ic/l->groups,l->oc/l->groups);
}
int a48_candidate(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{
    if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;
    return a48_post_block(l,x,y,w,p,l->ic/l->groups,l->oc/l->groups);
}
void *a48_scratch(void){return block_input_cache;}
