#ifdef YOLO_HOST_TEST
#include "../ai_1x1_block_layer/host_mmio.h"
#endif
#define main a30_unused_control_main
#include "../../yolo_fixed/main.c"
#undef main
int a30_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p)
{
    return conv3x3_rolling(l,x,y,w,p);
}
int32_t a30_old_scale(int32_t v,int32_t m){return apply_q24(v,m);}
int8_t a30_old_quant(int32_t v,int32_t m,int32_t b,uint32_t leaky){return dw3_quant(v,m,b,leaky);}
