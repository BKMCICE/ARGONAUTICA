/* Scalar differential checks of the production tiled convolution itself. */
#ifdef YOLO_HOST_TEST
#include <stdio.h>
#endif
#define main yolo_app_main
#include "../../yolo_fixed/main.c"
#undef main

#ifdef YOLO_HOST_TEST
uint32_t host_ai_calls;
static const uint32_t output_widths[]={1,7,8,9,11,12,13,17,23,24,25};
static const uint32_t widths[] = {10,16,17,18,19,24,31,32,48,96,120,136,192,223,224};
static int8_t input[224*3*3*33], kernels[75*224], actual[75*3*17+16];
#else
static const uint32_t output_widths[]={11,12,13};
static const uint32_t widths[] = {10,224};
static int8_t input[224*2*17], kernels[26*224], actual[26*9+16];
#endif

static int32_t params[150];

static uint32_t input_hash(void)
{
    uint32_t h=2166136261u;
    for (uint32_t i=0;i<sizeof(input);++i) h=(h^(uint8_t)input[i])*16777619u;
    return h;
}

static int32_t reference_scale(int64_t value, int32_t multiplier)
{
    int64_t product = value * multiplier;
    int64_t rounded = ((product < 0 ? -product : product) + 8388608) / 16777216;
    return (int32_t)(product < 0 ? -rounded : rounded);
}

#ifndef AI_BATCH12_TEST_ENTRY
#define AI_BATCH12_TEST_ENTRY main
#endif
int AI_BATCH12_TEST_ENTRY(void)
{
    uint32_t cases=0, rejected=0;
#if YOLO_1X1_ACC32
    /* Must reject before any pointer access, allocation or AI MMIO. */
    if (conv1x1_input_reuse(0,0,0,0,0,225,1)!=0) return 5;
    ++rejected;
    if (conv1x1_input_reuse(0,0,0,0,0,0xffffffffu,1)!=0) return 6;
    ++rejected;
#endif
    /* Parameters are static DDR data, outside the diagnostic TCM stack. */
#ifndef YOLO_HOST_TEST
    AI_BIAS=0;
#endif
    for (uint32_t groups=1; groups<=
#ifdef YOLO_HOST_TEST
         3
#else
         2
#endif
         ; ++groups)
    for (uint32_t ci=0; ci<sizeof(widths)/sizeof(widths[0]); ++ci)
    for (uint32_t ow=1; ow<=
#ifdef YOLO_HOST_TEST
         17
#else
         9
#endif
         ; ++ow)
    for (uint32_t stride=1; stride<=2; ++stride)
    for (uint32_t oi=0; oi<sizeof(output_widths)/sizeof(output_widths[0]); ++oi) {
        uint32_t outputs=output_widths[oi];
#ifdef YOLO_HOST_TEST
        if (ow!=1 && ow!=7 && ow!=8 && ow!=9 && ow!=17) continue;
#endif
#ifndef YOLO_HOST_TEST
        if (ow!=1 && ow!=9) continue;
        if (stride!=1+(oi&1)) continue;
#endif
        uint32_t channels=widths[ci];
        YoloLayer layer;
        layer.kind=YOLO_CONV; layer.size=1; layer.stride=stride;
        layer.ih=
#ifdef YOLO_HOST_TEST
            3;
#else
            1;
#endif
        layer.iw=(ow-1)*stride+1;
        layer.oh=(layer.ih+stride-1)/stride; layer.ow=ow;
        layer.ic=groups*channels; layer.oc=groups*outputs; layer.groups=groups;
        layer.leaky=cases&1;
        for (uint32_t i=0;i<sizeof(input);++i) input[i]=cases%6==0 ? -128 : cases%6==1 ? 127 : cases%6==2 ? 0 : cases%6==3 ? (i&1 ? -128:127) : (int8_t)((i*173u+cases*71u)&255u);
        for (uint32_t i=0;i<sizeof(kernels);++i) kernels[i]=cases%6==0 ? -128 : cases%6==1 ? -128 : cases%6==2 ? 127 : (int8_t)((i*59u+cases*127u)&255u);
        for (uint32_t i=0;i<75;++i) {
            params[i*2]=((i&1) ? -1 : 1)*((1<<18)+(int32_t)i*3989);
            params[i*2+1]=(int32_t)i*37-111;
        }
        for (uint32_t i=0;i<sizeof(actual);++i) actual[i]=0x5a;
        /* Seed every resident lane with stale values before a partial block. */
        if (ai_dot9_packed(0,0,0,0xdeadbeef,0x89abcdef,0x55)!=0) return 1;
        uint32_t before=input_hash();
#if YOLO_1X1_ACC32
        if (!conv1x1_input_reuse(&layer,input,actual+8,kernels,params,channels,outputs)) return 10;
#else
        conv1x1_input_reuse(&layer,input,actual+8,kernels,params,channels,outputs);
#endif
        if (input_hash()!=before) return 11;
        for (uint32_t oc=0;oc<layer.oc;++oc)
        for (uint32_t y=0;y<layer.oh;++y)
        for (uint32_t x=0;x<ow;++x) {
            int64_t dot=0;
            for (uint32_t c=0;c<channels;++c)
                dot+=(int32_t)input[((oc/outputs)*channels+c)*layer.ih*layer.iw+y*stride*layer.iw+x*stride]*kernels[oc*channels+c];
            int32_t expected=reference_scale(dot,params[oc*2])+params[oc*2+1];
            if(layer.leaky && expected<0) expected=reference_scale(expected,1677722);
            if(expected>127) expected=127;
            if(expected< -127) expected= -127;
            if(actual[8+(oc*layer.oh+y)*ow+x]!=expected) {
#ifdef YOLO_HOST_TEST
                printf("AI_BATCH12_FAIL case=%u oc=%u y=%u x=%u\n",cases,oc,y,x);
#else
                uart_puts("AI_BATCH12_FAIL scalar\n");
#endif
                return 2;
            }
        }
        for(uint32_t i=0;i<sizeof(actual);++i)
            if((i<8 || i>=8+layer.oc*layer.oh*ow) && actual[i]!=0x5a) return 3;
        ++cases;
    }
    /* Full-channel extrema stay below saturation after the independent Q24
     * scale, exposing sign/carry errors instead of hiding them by clipping. */
    for (uint32_t pattern=0; pattern<6; ++pattern) {
        YoloLayer layer;
        layer.kind=YOLO_CONV; layer.size=1; layer.stride=1;
        layer.ih=layer.oh=1; layer.iw=layer.ow=9;
        layer.ic=224; layer.oc=
#ifdef YOLO_HOST_TEST
            25;
#else
            13;
#endif
        layer.groups=1; layer.leaky=(pattern==5);
        for (uint32_t c=0;c<224;++c) {
            int8_t value=pattern==0 || pattern==1 ? -128 :
                         pattern==2 ? 127 : pattern==3 ? (c&1 ? 127:-128) :
                         pattern==4 ? 0 : (int8_t)(c*71u+139u);
            for (uint32_t x=0;x<9;++x) input[c*9+x]=value;
        }
        for (uint32_t oc=0;oc<layer.oc;++oc) {
            for (uint32_t c=0;c<224;++c)
                kernels[oc*224+c]=pattern==0 || pattern==3 ? -128 :
                                  pattern==1 || pattern==2 ? 127 : (int8_t)(c*43u+oc*19u);
            params[oc*2]=(oc&1 ? -1:1)*256;
            params[oc*2+1]=(int32_t)oc-4;
        }
        for (uint32_t i=0;i<sizeof(actual);++i) actual[i]=0x5a;
#if YOLO_1X1_ACC32
        if (!conv1x1_input_reuse(&layer,input,actual+8,kernels,params,224,layer.oc)) return 7;
#else
        conv1x1_input_reuse(&layer,input,actual+8,kernels,params,224,layer.oc);
#endif
        for (uint32_t oc=0;oc<layer.oc;++oc) for (uint32_t x=0;x<9;++x) {
            int64_t dot=0;
            for (uint32_t c=0;c<224;++c) dot+=(int32_t)input[c*9+x]*kernels[oc*224+c];
            int32_t expected=reference_scale(dot,params[oc*2])+params[oc*2+1];
            if (layer.leaky && expected<0) expected=reference_scale(expected,1677722);
            if (expected>127) expected=127;
            if (expected< -127) expected= -127;
            if (actual[8+oc*9+x]!=expected) return 8;
        }
        for (uint32_t i=0;i<sizeof(actual);++i)
            if ((i<8 || i>=8+layer.oc*9) && actual[i]!=0x5a) return 9;
        ++cases;
    }
#ifdef YOLO_HOST_TEST
    printf("AI_BATCH12_SCALAR_PASS cases=%u rejected=%u\n",cases,rejected);
    return cases==4956 ? 0 : 4;
#else
    uart_puts("AI_BATCH12_PASS cases="); uart_putdec(cases); uart_puts(" rejected="); uart_putdec(rejected); uart_putc('\n');
    return cases==30 && rejected==2 ? 0 : 4;
#endif
}
