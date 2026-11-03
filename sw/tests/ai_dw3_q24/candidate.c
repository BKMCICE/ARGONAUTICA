#ifdef YOLO_HOST_TEST
#include "../ai_1x1_block_layer/host_mmio.h"
#endif
#define host_dw3_rolling_calls a30_candidate_unused_host_calls
#define main a30_unused_candidate_main
#include "../../yolo_fixed/main.c"
#undef main
#undef host_dw3_rolling_calls
#include "fast_q24.h"
#include "candidate_rolling.h"
int a30_candidate(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{
    return a30_candidate_rolling(l,x,y,w,p);
}
int64_t a30_wide_scale(int32_t v,int32_t m){return a30_round_wide(v,m);}
int32_t a30_scale(int32_t v,int32_t m){return a30_round(v,m);}
int8_t a30_quant(int32_t v,int32_t m,int32_t b,uint32_t leaky){return a30_fast_quant(v,m,b,leaky);}
