#ifdef YOLO_HOST_TEST
#include "../ai_1x1_block_layer/host_mmio.h"
#define host_block_cached_groups a28_candidate_cached_groups
#define host_block_cached_pixels a28_candidate_cached_pixels
#endif
#define main a28_unused_candidate_main
#define YOLO_BLOCK_Q24_REUSE 1
#include "../../yolo_fixed/main.c"
#undef main
#include "pdata_reuse.h"
int a28_candidate(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{
    return a28_reuse(l,x,y,w,p);
}
void a28_store(const int32_t *a,int8_t *d,uint32_t n,int32_t m,int32_t b,uint32_t leaky)
{
    block_q24_store(a,d,n,m,b,leaky);
}

#ifdef YOLO_HOST_TEST
void *a28_scratch(unsigned i){return i ? (void *)a28_weight_cache : (void *)block_input_cache;}
#endif
