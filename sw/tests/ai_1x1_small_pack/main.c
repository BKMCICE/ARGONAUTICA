/* Independent packed-lane and production-convolution differential checks. */
#ifdef YOLO_HOST_TEST
#include <stdio.h>
#include "ai_mac.h"
uint32_t host_ai_calls;
static uint32_t checking, packing_failed, expected_pixels[3];
static int32_t checked_dot(uint32_t p0,uint32_t p1,uint32_t p2,
                           uint32_t w0,uint32_t w1,uint32_t w2)
{
    if (checking && (p0!=expected_pixels[0] || p1!=expected_pixels[1] || p2!=expected_pixels[2])) packing_failed=1;
    return ai_dot9_packed(p0,p1,p2,w0,w1,w2);
}
#define ai_dot9_packed checked_dot
#endif
#define main yolo_app_main
#include "../../yolo_fixed/main.c"
#undef main

static int8_t pixels[9*65+16], snapshot[9*65+16], weights[9];
static const uint32_t widths_order[]={9,8,4,7,3,8,4,1,2,5,6};
#ifdef YOLO_HOST_TEST
static const uint32_t planes[]={1,2,3,7,17,65};
#else
static const uint32_t planes[]={1,3,17};
#endif
static int8_t input[3*17*3*17+16], kernels[51*17], actual[51*3*9+16];
static int32_t params[102];

static int8_t sample(uint32_t i,uint32_t pattern)
{
    if (pattern==0) return (int8_t)(i*173u+71u);
    if (pattern==1) return -128;
    if (pattern==2) return 127;
    if (pattern==3) return 0;
    if (pattern==4) return i&1 ? 127:-128;
    if (pattern==5) return -1;
    return (int8_t)(i*(pattern*2u+1u)+139u);
}

static int32_t reference_scale(int64_t value,int32_t multiplier)
{
    int64_t product=value*multiplier;
    int64_t rounded=((product<0 ? -product:product)+8388608)/16777216;
    return (int32_t)(product<0 ? -rounded:rounded);
}

static int check_lanes(uint32_t *cases)
{
#ifndef YOLO_HOST_TEST
    AI_BIAS=0;
#endif
    for (uint32_t pi=0;pi<sizeof(planes)/sizeof(planes[0]);++pi)
    for (uint32_t wi=0;wi<sizeof(widths_order)/sizeof(widths_order[0]);++wi)
    for (uint32_t pattern=0;pattern<
#ifdef YOLO_HOST_TEST
         8
#else
         6
#endif
         ;++pattern) {
        uint32_t channels=widths_order[wi],plane=planes[pi];
        for (uint32_t i=0;i<sizeof(pixels);++i) pixels[i]=snapshot[i]=sample(i,pattern);
        for (uint32_t i=0;i<9;++i) weights[i]=sample(i+1,pattern==1?2:pattern);
        (void)ai_dot9_packed(0xffffffffu,0xffffffffu,0xffffffffu,0xdeadbeefu,0x89abcdefu,0x55u);
        ai_load_1x1_weights(weights,channels);
        uint32_t resident[3];
#ifdef YOLO_HOST_TEST
        for (uint32_t i=0;i<3;++i) resident[i]=host_resident_weights[i];
#else
        resident[0]=AI_WGT0;resident[1]=AI_WGT1;resident[2]=AI_WGT2;
#endif
        for (uint32_t pixel=0;pixel<plane;++pixel) {
            uint32_t expected[3]={0,0,0};
            int32_t dot=0;
            for (uint32_t word=0;word<3;++word) for (uint32_t byte=0;byte<4;++byte) {
                uint32_t ch=word*4+byte;
                if(ch<channels) expected[word]+=(uint32_t)(uint8_t)snapshot[1+ch*plane+pixel]*(1u<<(byte*8));
            }
            for(uint32_t ch=0;ch<channels;++ch) dot+=(int32_t)snapshot[1+ch*plane+pixel]*weights[ch];
#ifdef YOLO_HOST_TEST
            for(uint32_t i=0;i<3;++i) expected_pixels[i]=expected[i];
            checking=1;
#endif
            int32_t got=ai_dot1x1_loaded(pixels+1,plane,pixel,channels);
#ifdef YOLO_HOST_TEST
            checking=0;
            if(packing_failed) return 1;
            for(uint32_t i=0;i<3;++i) if(host_resident_weights[i]!=resident[i]) return 2;
#else
            if(AI_PIX0!=expected[0] || AI_PIX1!=expected[1] || AI_PIX2!=expected[2]) return 1;
            if(AI_WGT0!=resident[0] || AI_WGT1!=resident[1] || AI_WGT2!=resident[2]) return 2;
#endif
            if(got!=dot) return 3;
            ++*cases;
        }
        for(uint32_t i=0;i<sizeof(pixels);++i) if(pixels[i]!=snapshot[i]) return 4;
    }
    return 0;
}

__attribute__((noinline)) static int check_conv(uint32_t ci,uint32_t outputs,
    uint32_t groups,uint32_t ow,uint32_t stride,uint32_t pattern,uint32_t tiled)
{
    YoloLayer l;
    l.kind=YOLO_CONV;l.size=1;l.stride=stride;l.groups=groups;
    l.ih=
#ifdef YOLO_HOST_TEST
        3;
#else
        1;
#endif
    l.iw=(ow-1)*stride+1;l.oh=(l.ih+stride-1)/stride;l.ow=ow;
    l.ic=groups*ci;l.oc=groups*outputs;l.leaky=pattern&1;
    for(uint32_t i=0;i<sizeof(input);++i) input[i]=sample(i,pattern);
    for(uint32_t i=0;i<sizeof(kernels);++i) kernels[i]=sample(i+7,pattern==1?2:(pattern==2?1:pattern));
    for(uint32_t oc=0;oc<l.oc;++oc) {
        params[oc*2]=(oc&1 ? -1:1)*(pattern==0 ? 262144:256);
        params[oc*2+1]=(int32_t)(oc%9)-4;
    }
    for(uint32_t i=0;i<sizeof(actual);++i) actual[i]=0x5a;
    if(ai_dot9_packed(0,0,0,0xdeadbeefu,0x89abcdefu,0x55u)!=0) return 5;
#if YOLO_TILE_1X1_WEIGHTS && !YOLO_REUSE_1X1_INPUT
    if(tiled) conv1x1_tiled(&l,input+8,actual+8,kernels,params,ci,outputs);
    else
#else
    (void)tiled;
#endif
    conv1x1_small(&l,input+8,actual+8,kernels,params,ci,outputs);
    for(uint32_t oc=0;oc<l.oc;++oc)
    for(uint32_t y=0;y<l.oh;++y) for(uint32_t x=0;x<ow;++x) {
        int64_t dot=0;
        for(uint32_t c=0;c<ci;++c)
            dot+=(int32_t)input[8+((oc/outputs)*ci+c)*l.ih*l.iw+y*stride*l.iw+x*stride]*kernels[oc*ci+c];
        int32_t expected=reference_scale(dot,params[oc*2])+params[oc*2+1];
        if(l.leaky && expected<0) expected=reference_scale(expected,1677722);
        if(expected>127) expected=127;
        if(expected< -127) expected= -127;
        if(actual[8+(oc*l.oh+y)*ow+x]!=expected) return 6;
    }
    for(uint32_t i=0;i<sizeof(actual);++i)
        if((i<8 || i>=8+l.oc*l.oh*ow) && actual[i]!=0x5a) return 7;
    return 0;
}

int main(void)
{
    uint32_t dots=0,convs=0,alternate=0;
    int error=check_lanes(&dots);
    if(error) return error;
#ifdef YOLO_HOST_TEST
    const uint32_t inputs[]={1,2,3,4,5,6,7,8,9};
    const uint32_t outputs[]={1,4,7,8,9,17},widths[]={1,7,8,9};
    const uint32_t max_groups=3;
#else
    const uint32_t inputs[]={4,8},outputs[]={1,9},widths[]={1,9};
    const uint32_t max_groups=2;
#endif
    for(uint32_t g=1;g<=max_groups;++g)
    for(uint32_t ci=0;ci<sizeof(inputs)/sizeof(inputs[0]);++ci)
    for(uint32_t oi=0;oi<sizeof(outputs)/sizeof(outputs[0]);++oi)
    for(uint32_t wi=0;wi<sizeof(widths)/sizeof(widths[0]);++wi)
    for(uint32_t stride=1;stride<=2;++stride)
    for(uint32_t pattern=0;pattern<6;++pattern) {
        error=check_conv(inputs[ci],outputs[oi],g,widths[wi],stride,pattern,0);
        if(error) return error;
        ++convs;
    }
#if YOLO_TILE_1X1_WEIGHTS && !YOLO_REUSE_1X1_INPUT
    for(uint32_t g=1;g<=max_groups;++g)
    for(uint32_t ci=13;ci<=17;ci+=4)
    for(uint32_t oi=0;oi<sizeof(outputs)/sizeof(outputs[0]);++oi)
    for(uint32_t wi=0;wi<sizeof(widths)/sizeof(widths[0]);++wi)
    for(uint32_t stride=1;stride<=2;++stride)
    for(uint32_t pattern=0;pattern<6;++pattern) {
        error=check_conv(ci,outputs[oi],g,widths[wi],stride,pattern,1);
        if(error) return error;
        ++alternate;
    }
#endif
#ifdef YOLO_HOST_TEST
    printf("AI_SMALL_PACK_SCALAR_PASS dots=%u convs=%u alternate=%u\n",dots,convs,alternate);
    return dots==8360 && convs==7776 && (alternate==0 || alternate==1728) ? 0:8;
#else
    uart_puts("AI_SMALL_PACK_PASS dots=");uart_putdec(dots);
    uart_puts(" convs=");uart_putdec(convs);uart_puts(" alternate=");uart_putdec(alternate);uart_putc('\n');
    return dots==1386 && convs==192 && alternate==0 ? 0:8;
#endif
}
