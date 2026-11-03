#ifdef YOLO_HOST_TEST
#include "host_mmio.h"
#endif
#define main a88_unused_production_main
#include "../../yolo_fixed/main.c"
#undef main
#include "../../yolo_fixed/post8_word_store.h"
#define DW5_PACK_INPUT dw5_pack_fast
#include "candidate.inc"
#undef DW5_PACK_INPUT
int a88_control(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*k,const int32_t*p){return conv5x5_block(l,x,y,k,p);}
int a88_placebo(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*k,const int32_t*p){return a88_placebo_block(l,x,y,k,p);}
int a88_candidate(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*k,const int32_t*p){return a88_candidate_block(l,x,y,k,p);}
#ifdef YOLO_HOST_TEST
void a88_store_bridge(int8_t*d,uint32_t word,uint32_t n){post8_word_store(d,word,n);}
#endif
