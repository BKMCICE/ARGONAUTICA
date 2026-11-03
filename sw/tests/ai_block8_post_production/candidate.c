/* Exercise the actual shared production function, not an extracted clone. */
#ifdef YOLO_HOST_TEST
#include "host_mmio.h"
#endif
#undef YOLO_BLOCK_POST8
#define YOLO_BLOCK_POST8 1
#define main unused_candidate_main
#include "../../yolo_fixed/main.c"
#undef main
int a48_candidate(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *v,const int32_t *p)
{if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;return conv1x1_block(l,x,y,v,p,l->ic/l->groups,l->oc/l->groups);}
void *a50_candidate_scratch(void){return block_input_cache;}
