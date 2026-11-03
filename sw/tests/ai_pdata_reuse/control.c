#ifdef YOLO_HOST_TEST
#include "../ai_1x1_block_layer/host_mmio.h"
#endif
#define main a28_unused_control_main
#define YOLO_BLOCK_Q24_REUSE 1
#include "../../yolo_fixed/main.c"
#undef main
int a28_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{
    if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;
    return conv1x1_block(l,x,y,w,p,l->ic/l->groups,l->oc/l->groups);
}
