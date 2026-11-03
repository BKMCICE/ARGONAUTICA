#ifdef YOLO_HOST_TEST
#include "../ai_post8_word_store/host_mmio.h"
#endif
#define main a82_unused_production_main
#include "../../yolo_fixed/main.c"
#undef main
#include "cache_pack4.h"
#include "candidate.inc"
int a82_control(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*k,const int32_t*p){if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;return conv1x1_block(l,x,y,k,p,l->ic/l->groups,l->oc/l->groups);}
int a82_placebo(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*k,const int32_t*p){if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;return a82_placebo_block(l,x,y,k,p,l->ic/l->groups,l->oc/l->groups);}
int a82_candidate(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*k,const int32_t*p){if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;return a82_candidate_block(l,x,y,k,p,l->ic/l->groups,l->oc/l->groups);}
void *a82_scratch(void){return block_input_cache;}
#ifdef YOLO_HOST_TEST
void a82_store_bridge(int8_t*d,uint32_t v,uint32_t n){post8_word_store(d,v,n);}
unsigned a82_fast_calls(void){return a82_fast_pack_calls;}
void a82_cache_bridge(const YoloLayer*l,const int8_t*x,unsigned channels,int candidate){if(candidate)a82_cache_pack(l,x,l->ih*l->iw,l->oh*l->ow,channels,(channels+8)/9);else block_cache_pack(l,x,l->ih*l->iw,l->oh*l->ow,channels,(channels+8)/9);}
#endif
