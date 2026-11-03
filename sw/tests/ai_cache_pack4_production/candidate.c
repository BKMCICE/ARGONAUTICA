#include "../ai_post8_word_store/host_mmio.h"
#define host_block_cached_groups a83_candidate_groups
#define host_block_cached_pixels a83_candidate_pixels
#define main a83_candidate_unused_main
#include "../../yolo_fixed/main.c"
#undef main
int a82_candidate(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*k,const int32_t*p){if(!l||!l->groups)return AI_BLOCK_BAD_SHAPE;return conv1x1_block(l,x,y,k,p,l->ic/l->groups,l->oc/l->groups);}
void *a82_scratch(void){return block_input_cache;}
void a82_store_bridge(int8_t*d,uint32_t v,uint32_t n){post8_word_store(d,v,n);}
unsigned a82_fast_calls(void){return cache_pack4_fast_calls;}
void a82_cache_bridge(const YoloLayer*l,const int8_t*x,unsigned channels,int candidate){if(candidate)block_cache_pack(l,x,l->ih*l->iw,l->oh*l->ow,channels,(channels+8)/9);else block_cache_pack_scalar(l,x,l->ih*l->iw,l->oh*l->ow,channels,(channels+8)/9);}
