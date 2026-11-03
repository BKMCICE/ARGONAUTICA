#ifdef YOLO_HOST_TEST
#include "../ai_1x1_block_layer/host_mmio.h"
#endif
#define main a19_unused_control_main
#define YOLO_LAYER_PROFILE 0
#define YOLO_BLOCK_PHASE_PROFILE 0
#define YOLO_BLOCK_CACHE_PHASE_PROFILE 0
#include "../../yolo_fixed/main.c"
#undef main
int a19_control(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p){
 return conv1x1_block(l,x,y,w,p,l->ic/l->groups,l->oc/l->groups);
}
