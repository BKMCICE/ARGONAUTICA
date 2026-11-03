#ifdef YOLO_HOST_TEST
#include "host_mmio.h"
#endif
#define main a79_unused_production_main
#include "../../yolo_fixed/main.c"
#undef main
#include "store.h"
#include "candidate.inc"
int a79_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;return conv1x1_block(l,x,y,w,p,l->ic/l->groups,l->oc/l->groups);}
int a79_placebo(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;return a79_placebo_block(l,x,y,w,p,l->ic/l->groups,l->oc/l->groups);}
int a79_candidate(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;return a79_word_block(l,x,y,w,p,l->ic/l->groups,l->oc/l->groups);}
void *a79_scratch(void){return block_input_cache;}
#ifdef YOLO_HOST_TEST
void a79_store_bridge(int8_t *d,uint32_t word,uint32_t n){a79_store(d,word,n);}
#endif
