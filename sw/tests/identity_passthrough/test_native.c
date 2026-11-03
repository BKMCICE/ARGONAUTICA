/* Exact production passthrough, with an independent division oracle. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include "../../yolo_fixed/model_graph.h"
void a68_control(const YoloLayer *, const int8_t *, int8_t *);
void a68_candidate(const YoloLayer *, const int8_t *, int8_t *);
#define CAP 102400u
static int8_t input[CAP+16],before[CAP+16],control[CAP+16],candidate[CAP+16],alias[CAP+16];
static uint64_t checks;
static unsigned cases,model_layers;
#define CHECK(x) do {++checks;if(!(x)){fprintf(stderr,"A68_NATIVE_FAIL case=%u line=%d\n",cases,__LINE__);exit(1);}}while(0)
static int8_t oracle(int8_t x,int32_t q) {
    int64_t p=(int64_t)x*q;
    int64_t v=p>=0?(p+8388608)/16777216:-((-p+8388608)/16777216);
    return (int8_t)(v>127?127:v< -127?-127:v);
}
static void run(YoloLayer layer,unsigned inplace) {
    uint32_t n=layer.oh*layer.ow*layer.oc;CHECK(n<=CAP);++cases;
    for(uint32_t i=0;i<CAP+16;++i)input[i]=(int8_t)((int32_t)(i&255u)-128);
    memcpy(before,input,sizeof input);memset(control,0x5d,sizeof control);memset(candidate,0x5d,sizeof candidate);
    a68_control(&layer,input,control);a68_candidate(&layer,input,candidate);
    CHECK(!memcmp(input,before,sizeof input));
    for(uint32_t i=0;i<n;++i)CHECK(control[i]==oracle(input[i],layer.prev_q24)&&candidate[i]==oracle(input[i],layer.prev_q24));
    for(uint32_t i=n;i<CAP+16;++i)CHECK(control[i]==0x5d&&candidate[i]==0x5d);
    if(inplace) {
        memcpy(alias,input,sizeof input);a68_candidate(&layer,alias,alias);
        for(uint32_t i=0;i<n;++i)CHECK(alias[i]==oracle(input[i],layer.prev_q24));
        CHECK(!memcmp(alias+n,input+n,sizeof input-n));
    }
}
int main(void) {
    YoloLayer zero={0};zero.prev_q24=16777216;
    a68_control(&zero,0,0);a68_candidate(&zero,0,0);
    zero.prev_q24=INT32_MIN;a68_control(&zero,0,0);a68_candidate(&zero,0,0);
    for(unsigned i=0;i<YOLO_LAYER_COUNT;++i)if(yolo_layers[i].kind==YOLO_DROPOUT||yolo_layers[i].kind==YOLO_HEAD) {
        CHECK(yolo_layers[i].prev_q24==16777216);++model_layers;run(yolo_layers[i],0);
    }
    const int32_t q[]={0,1,-1,8388607,8388608,8388609,16777215,16777216,16777217,-16777216,INT32_MIN,INT32_MAX};
    const uint32_t n[]={1,3,4,5,255,256,257,1023};
    for(unsigned j=0;j<sizeof(q)/sizeof(q[0]);++j)for(unsigned k=0;k<sizeof(n)/sizeof(n[0]);++k) {
        YoloLayer l={0};l.oh=1;l.ow=n[k];l.oc=1;l.prev_q24=q[j];run(l,1);
    }
    CHECK(model_layers==20);
    printf("A68_NATIVE_PASS cases=%u checks=%llu model_layers=%u\n",cases,(unsigned long long)checks,model_layers);
    return 0;
}
