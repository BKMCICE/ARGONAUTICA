#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include "../../yolo_fixed/model_graph.h"
#define INT8_SHORTCUT_LUT_TYPES_ONLY
#include "../../common/int8_shortcut_lut.h"
void a65_control(const YoloLayer *,const int8_t *,const int8_t *,int8_t *);
void a65_candidate(const YoloLayer *,const int8_t *,const int8_t *,int8_t *,Int8ShortcutLut *);
#define CAP 102400u
static int8_t input[CAP+16],source[CAP+16],control[CAP+16],candidate[CAP+16],oracle[CAP+16],alias[CAP+16];
static struct { uint32_t before; Int8ShortcutLut lut; uint32_t after; } scratch;
static uint64_t checks;
static unsigned cases;
#define CHECK(v) do { ++checks; if (!(v)) {fprintf(stderr,"A65_NATIVE_FAIL line=%d case=%u\n",__LINE__,cases);exit(1);} } while(0)
static int32_t quant(int32_t x,int32_t m) {
    int64_t p=(int64_t)x*m;
    return p>=0?(int32_t)((p+8388608)/16777216):-(int32_t)((-p+8388608)/16777216);
}
static int8_t clip(int32_t x) {return (int8_t)(x>127?127:x< -127?-127:x);}
static int8_t signed_byte(uint32_t x) {x&=255;return (int8_t)(x<128?(int32_t)x:(int32_t)x-256);}
static uint32_t hash(const int8_t *p,uint32_t n) {uint32_t h=2166136261u;for(uint32_t i=0;i<n;++i)h=(h^(uint8_t)p[i])*16777619u;return h;}
static void run(YoloLayer layer,unsigned exhaustive,unsigned test_alias) {
    uint32_t n=layer.oh*layer.ow*layer.oc;CHECK(n<=CAP);++cases;
    for(uint32_t i=0;i<n;++i) {
        input[i]=exhaustive?(int8_t)((int32_t)(i>>8)-128):signed_byte((i*73+cases*17)^(i>>8));
        source[i]=exhaustive?(int8_t)((int32_t)(i&255)-128):signed_byte(i*151+cases*23+5);
        oracle[i]=clip(quant(input[i],layer.prev_q24)+quant(source[i],layer.source_q24[0]));
    }
    uint32_t xhash=hash(input,n),yhash=hash(source,n);
    memset(control,0x5d,sizeof control);memset(candidate,0x5d,sizeof candidate);
    scratch.before=0x51acb009;scratch.after=0x21d3a71f;memset(&scratch.lut,0xa6,sizeof scratch.lut);
    a65_control(&layer,input,source,control);
    a65_candidate(&layer,input,source,candidate,&scratch.lut);
    CHECK(hash(input,n)==xhash && hash(source,n)==yhash);
    CHECK(scratch.before==0x51acb009 && scratch.after==0x21d3a71f);
    for(uint32_t i=0;i<n;++i)CHECK(control[i]==oracle[i] && candidate[i]==oracle[i]);
    for(uint32_t i=n;i<CAP+16;++i)CHECK(control[i]==0x5d && candidate[i]==0x5d);
    if(n)for(uint32_t i=0;i<256;++i) {
        int32_t x=i<128?(int32_t)i:(int32_t)i-256;
        CHECK(scratch.lut.values[0][i]==quant(x,layer.prev_q24));
        CHECK(scratch.lut.values[1][i]==quant(x,layer.source_q24[0]));
    }
    if(test_alias) {
        memcpy(alias,input,n);a65_candidate(&layer,alias,source,alias,&scratch.lut);
        for(uint32_t i=0;i<n;++i)CHECK(alias[i]==oracle[i]);
        memcpy(alias,source,n);a65_candidate(&layer,input,alias,alias,&scratch.lut);
        for(uint32_t i=0;i<n;++i)CHECK(alias[i]==oracle[i]);
        for(uint32_t i=0;i<n;++i)oracle[i]=clip(quant(input[i],layer.prev_q24)+quant(input[i],layer.source_q24[0]));
        a65_candidate(&layer,input,input,candidate,&scratch.lut);
        for(uint32_t i=0;i<n;++i)CHECK(candidate[i]==oracle[i]);
    }
}
int main(void) {
    CHECK(sizeof(Int8ShortcutLut)==1024);
    YoloLayer zero={0};a65_control(&zero,0,0,0);a65_candidate(&zero,0,0,0,0);
    for(unsigned i=0;i<YOLO_LAYER_COUNT;++i)if(yolo_layers[i].kind==YOLO_SHORTCUT) {
        run(yolo_layers[i],0,0);
        YoloLayer layer=yolo_layers[i];layer.oh=1;layer.ow=65536;layer.oc=1;run(layer,1,0);
    }
    static const int32_t stress[][2]={
        {0,0},{1,-1},{8388608,-8388608},{16777216,-16777216},{INT32_MIN,INT32_MAX},
        {INT32_MIN,INT32_MIN},{INT32_MAX,INT32_MAX},{INT32_MAX,INT32_MIN},
        {16777215,16777217},{-16777215,-16777217},{8388607,8388609},{-8388607,-8388609}};
    for(unsigned i=0;i<sizeof stress/sizeof stress[0];++i) {
        YoloLayer layer={0};layer.oh=1;layer.ow=65536;layer.oc=1;layer.prev_q24=stress[i][0];layer.source_q24[0]=stress[i][1];run(layer,1,0);
    }
    static const uint32_t tails[]={1,2,3,4,7,8,15,31,63,255,256,257};
    for(unsigned i=0;i<sizeof tails/sizeof tails[0];++i) {
        YoloLayer layer={0};layer.oh=1;layer.ow=tails[i];layer.oc=1;layer.prev_q24=-16777217;layer.source_q24[0]=INT32_MAX;run(layer,0,1);
    }
    printf("A65_NATIVE_PASS cases=%u checks=%llu scratch=%u model_shortcuts=18 exhaustive_pairs=65536\n",cases,(unsigned long long)checks,(unsigned)sizeof(Int8ShortcutLut));
    return 0;
}
