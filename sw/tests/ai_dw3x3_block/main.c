/* Isolated A10 operator; no production dispatch switch is changed. */
#ifdef YOLO_HOST_TEST
#include <stdio.h>
#include <string.h>
#include "../ai_1x1_block_layer/host_mmio.h"
uint32_t host_ai_calls;
#endif
#define main yolo_app_main
#include "../../yolo_fixed/main.c"
#undef main
#include "operator.h"
#ifndef YOLO_HOST_TEST
volatile uint32_t a10_result;
void *memset(void *dest,int value,__SIZE_TYPE__ n) {
    volatile unsigned char *p=dest;for(__SIZE_TYPE__ i=0;i<n;++i)p[i]=(unsigned char)value;return dest;
}
#endif
static int8_t src[8*43*43+16],weights[8*9+16],actual[8*43*43+16],prior[8*43*43+16];
static int32_t params[16];
static uint32_t cases,guards;
static uint32_t hash(const void *data,uint32_t n) {
    const uint8_t *p=data;uint32_t v=2166136261u;for(uint32_t i=0;i<n;++i)v=(v^p[i])*16777619u;return v;
}
static void prepare(uint32_t seed) {
    for(uint32_t i=0;i<sizeof(src);++i)src[i]=seed%3==0?(i&1?-128:127):seed%3==1?-128:(int8_t)(i*73u+seed*19u);
    for(uint32_t i=0;i<sizeof(weights);++i)weights[i]=seed%3==1?-128:(int8_t)(i*59u+seed*31u);
    for(uint32_t i=0;i<8;++i){params[2*i]=(i&1?-1:1)*(seed%3==1?256:16384+(int32_t)i*29);params[2*i+1]=(int32_t)i-4;}
    for(uint32_t i=0;i<sizeof(actual);++i)actual[i]=prior[i]=0x5a;
}
/* Independent original CHW and division-based Q24 oracle. */
static int32_t scale(int64_t dot,int32_t m) {
    int64_t p=dot*m,n=((p<0?-p:p)+8388608)/16777216;return (int32_t)(p<0?-n:n);
}
static int check(const YoloLayer *l,const int8_t *out) {
    for(uint32_t c=0;c<l->oc;++c)for(uint32_t y=0;y<l->oh;++y)for(uint32_t x=0;x<l->ow;++x){
        int64_t dot=0;
        for(uint32_t ky=0;ky<3;++ky)for(uint32_t kx=0;kx<3;++kx){
            int32_t yy=(int32_t)(y*l->stride+ky)-(int32_t)l->pad,xx=(int32_t)(x*l->stride+kx)-(int32_t)l->pad;
            if(yy>=0 && yy<(int32_t)l->ih && xx>=0 && xx<(int32_t)l->iw)
                dot+=(int32_t)src[8+(c*l->ih+(uint32_t)yy)*l->iw+(uint32_t)xx]*weights[8+c*9+ky*3+kx];
        }
        int32_t v=scale(dot,params[2*c])+params[2*c+1];if(l->leaky && v<0)v=scale(v,1677722);
        if(v>127)v=127;
        if(v< -127)v=-127;
        if(out[8+(c*l->oh+y)*l->ow+x]!=v)return 1;
    }
    uint32_t n=l->oc*l->oh*l->ow;
    for(uint32_t i=0;i<sizeof(actual);++i)if((i<8 || i>=8+n)&&out[i]!=0x5a)return 2;
    return 0;
}
static YoloLayer shape(uint32_t h,uint32_t w,uint32_t c,uint32_t stride,uint32_t pad){
    YoloLayer l={0};l.kind=YOLO_CONV;l.size=3;l.ih=h;l.iw=w;l.ic=l.oc=l.groups=c;l.stride=stride;l.pad=pad;
    l.oh=(h+2*pad-3)/stride+1;l.ow=(w+2*pad-3)/stride+1;return l;
}
static int run_case(YoloLayer l,uint32_t seed) {
    prepare(seed);l.leaky=seed&1;uint32_t sh=hash(src,sizeof(src)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
#ifdef YOLO_HOST_TEST
    a03_reset(0);
#endif
    if(a10_conv3x3_block(&l,src+8,actual+8,weights+8,params))return 10;
    if(check(&l,actual))return 11;
    if(hash(src,sizeof(src))!=sh||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 12;
#ifdef YOLO_HOST_TEST
    if(a03_weight_words!=l.oc*3 || a03_pixel_words!=l.oc*l.oh*l.ow*3 || a03_starts!=l.oc*l.oh*((l.ow+7)/8))return 13;
#endif
    ++cases;return 0;
}
#ifdef YOLO_HOST_TEST
static int selected(const YoloLayer *l) {
    int rc=a10_conv3x3_block(l,src+8,actual+8,weights+8,params);
    if(rc==AI_BLOCK_UNSUPPORTED){conv3x3_depthwise_reuse(l,src+8,actual+8,weights+8,params);return 0;}
    return rc;
}
#endif
int main(void){
#ifdef YOLO_HOST_TEST
    const uint32_t hs[]={1,2,3,5},ws[]={1,2,3,7,8,9,10,17};uint32_t pads=3,seeds=3;
#else
    const uint32_t hs[]={1,3,5},ws[]={1,9,17};uint32_t pads=2,seeds=1;
    if(AI_BLOCK_READ(AI_BLOCK_REG_ID)!=AI_BLOCK_ID)return 90;
    AI_BIAS=0;
#endif
    for(uint32_t h=0;h<sizeof(hs)/sizeof(hs[0]);++h)for(uint32_t w=0;w<sizeof(ws)/sizeof(ws[0]);++w)
    for(uint32_t pad=0;pad<pads;++pad)for(uint32_t stride=1;stride<=2;++stride)for(uint32_t c=1;c<=2;++c)
    for(uint32_t seed=0;seed<seeds;++seed){
        if(hs[h]+2*pad<3 || ws[w]+2*pad<3)continue;
        YoloLayer l=shape(hs[h],ws[w],c,stride,pad);
        if(seed==2){if(l.oh>1)--l.oh;if(l.ow>1)--l.ow;}
        int rc=run_case(l,cases+seed);if(rc)return rc;
    }
    YoloLayer l=shape(5,17,2,1,1);
#ifdef YOLO_HOST_TEST
    a03_reset(0);uint32_t reads=a03_reads,writes=a03_writes;
#endif
#define BAD(expr) do{YoloLayer v=l;expr;if(a10_conv3x3_block(&v,src+8,actual+8,weights+8,params)!=AI_BLOCK_BAD_SHAPE)return 20;++guards;}while(0)
    BAD(v.kind=YOLO_ROUTE);BAD(v.size=1);BAD(v.groups=1);BAD(v.ic=0);BAD(v.oc=1);BAD(v.stride=0);
    BAD(v.stride=UINT32_MAX);BAD(v.pad=3);BAD(v.ih=0);BAD(v.iw=0);BAD(v.oh=0);BAD(v.ow=0);
    BAD(v.oh=100);BAD(v.ow=100);BAD(v.ih=INT32_MAX);BAD(v.iw=UINT32_MAX);BAD(v.ic=v.oc=v.groups=UINT32_MAX);
#undef BAD
    if(a10_conv3x3_block(0,0,0,0,0)!=AI_BLOCK_BAD_SHAPE ||
       a10_conv3x3_block(&l,src+8,(int8_t *)src+8,weights+8,params)!=AI_BLOCK_BAD_SHAPE ||
       a10_conv3x3_block(&l,src+8,(int8_t *)weights+8,weights+8,params)!=AI_BLOCK_BAD_SHAPE ||
       a10_conv3x3_block(&l,src+8,(int8_t *)params,weights+8,params)!=AI_BLOCK_BAD_SHAPE)return 21;
    guards+=4;
#ifdef YOLO_HOST_TEST
    if(a03_reads!=reads||a03_writes!=writes)return 22;
    const void *bad=(const void *)(UINTPTR_MAX-4);
    if(a10_conv3x3_block(&l,bad,actual+8,weights+8,params)!=AI_BLOCK_BAD_SHAPE ||
       a10_conv3x3_block(&l,src+8,(int8_t *)bad,weights+8,params)!=AI_BLOCK_BAD_SHAPE ||
       a10_conv3x3_block(&l,src+8,actual+8,bad,params)!=AI_BLOCK_BAD_SHAPE ||
       a10_conv3x3_block(&l,src+8,actual+8,weights+8,bad)!=AI_BLOCK_BAD_SHAPE)return 23;
    guards+=4;if(a03_reads!=reads||a03_writes!=writes)return 24;
    for(unsigned mode=1;mode<=6;++mode){
        prepare(8);a03_reset(mode);int expect=mode==1?AI_BLOCK_UNSUPPORTED:mode==3||mode==6?AI_BLOCK_TIMEOUT:AI_BLOCK_HW_ERROR;
        if(a10_conv3x3_block(&l,src+8,actual+8,weights+8,params)!=expect)return 25;
        if(mode<=2 && a03_writes)return 26;
        if(mode!=6){for(uint32_t i=0;i<sizeof(actual);++i)if(actual[i]!=0x5a)return 27;}
        else {for(uint32_t i=16;i<sizeof(actual);++i)if(actual[i]!=0x5a)return 28;}
        ++guards;
    }
    /* Actual selection wrapper for the isolated prototype, not production
     * YOLO dispatch: missing ID uses legacy, HW errors must not fall back. */
    prepare(7);a03_reset(0);if(selected(&l)||check(&l,actual))return 34;
    memcpy(prior,actual,sizeof(actual));prepare(7);a03_reset(1);
    if(selected(&l)||check(&l,actual)||a03_writes)return 35;
    /* prepare resets prior, so compare both paths independently to the oracle. */
    prepare(7);a03_reset(4);host_ai_calls=0;
    if(selected(&l)!=AI_BLOCK_HW_ERROR||host_ai_calls)return 36;
    guards+=3;
    printf("A10_SCALAR_PASS cases=%u guards=%u\n",cases,guards);return 0;
#else
    /* Warm each full operator; timed ABBA order, includes packing/Q24/DDR/MMIO. */
    for(uint32_t scenario=0;scenario<3;++scenario){
        l=shape(scenario==2?5:40,scenario==2?17:40,scenario==2?2:4,scenario==1?2:1,1);l.leaky=1;prepare(8);
        conv3x3_depthwise_reuse(&l,src+8,prior+8,weights+8,params);
        if(a10_conv3x3_block(&l,src+8,actual+8,weights+8,params))return 30;
        for(uint32_t sample=0;sample<4;++sample){
            uint64_t a,b,t;
            if(sample&1){t=rdcycle64();if(a10_conv3x3_block(&l,src+8,actual+8,weights+8,params))return 31;b=rdcycle64()-t;
                t=rdcycle64();conv3x3_depthwise_reuse(&l,src+8,prior+8,weights+8,params);a=rdcycle64()-t;
            }else{t=rdcycle64();conv3x3_depthwise_reuse(&l,src+8,prior+8,weights+8,params);a=rdcycle64()-t;
                t=rdcycle64();if(a10_conv3x3_block(&l,src+8,actual+8,weights+8,params))return 32;b=rdcycle64()-t;}
            if(check(&l,actual)||check(&l,prior))return 33;
            uart_puts("A10_BENCH scenario=");uart_putdec(scenario);uart_puts(" sample=");uart_putdec(sample);
            uart_puts(" legacy_cycles=");uart_putdec((uint32_t)a);uart_puts(" block_cycles=");uart_putdec((uint32_t)b);uart_putc('\n');
        }
    }
    uart_puts("A10_OPERATOR_PASS cases=");uart_putdec(cases);uart_puts(" guards=");uart_putdec(guards);uart_putc('\n');
    a10_result=1;return 0;
#endif
}
