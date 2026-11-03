/* Scalar differential checks of the production tiled convolution itself. */
#ifdef YOLO_HOST_TEST
#include <stdio.h>
#endif
#define main yolo_app_main
#include "../../yolo_fixed/main.c"
#undef main

#ifdef YOLO_HOST_TEST
uint32_t host_ai_calls;
static const uint32_t output_widths[]={1,3,4,5,7,8,9,15,16};
static const uint32_t widths[] = {10,16,17,18,19,24,31,32,48,96,120,136,192,223,224};
static int8_t input[224*3*3*33], kernels[48*224], actual[48*3*17+16];
#else
static const uint32_t output_widths[]={7,8,9};
static const uint32_t widths[] = {10,224};
static int8_t input[224*2*17], kernels[18*224], actual[18*9+16];
#endif

static int32_t reference_scale(int64_t value, int32_t multiplier)
{
    int64_t product = value * multiplier;
    int64_t rounded = ((product < 0 ? -product : product) + 8388608) / 16777216;
    return (int32_t)(product < 0 ? -rounded : rounded);
}

int main(void)
{
    uint32_t cases=0;
    int32_t params[96];
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
        for (uint32_t i=0;i<sizeof(input);++i) input[i]=(int8_t)((i*173u+cases*71u)&255u);
        for (uint32_t i=0;i<sizeof(kernels);++i) kernels[i]=(int8_t)((i*59u+cases*127u)&255u);
        for (uint32_t i=0;i<48;++i) {
            params[i*2]=((i&1) ? -1 : 1)*((1<<18)+(int32_t)i*3989);
            params[i*2+1]=(int32_t)i*37-111;
        }
        for (uint32_t i=0;i<sizeof(actual);++i) actual[i]=0x5a;
        /* Seed every resident lane with stale values before a partial block. */
        if (ai_dot9_packed(0,0,0,0xdeadbeef,0x89abcdef,0x55)!=0) return 1;
        conv1x1_input_reuse(&layer,input,actual+8,kernels,params,channels,outputs);
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
                printf("AI_INPUT_BATCH8_FAIL case=%u oc=%u y=%u x=%u\n",cases,oc,y,x);
#else
                uart_puts("AI_INPUT_BATCH8_FAIL scalar\n");
#endif
                return 2;
            }
        }
        for(uint32_t i=0;i<sizeof(actual);++i)
            if((i<8 || i>=8+layer.oc*layer.oh*ow) && actual[i]!=0x5a) return 3;
        ++cases;
    }
#ifdef YOLO_HOST_TEST
    printf("AI_INPUT_BATCH8_SCALAR_PASS cases=%u\n",cases);
    return cases==13770 ? 0 : 4;
#else
    uart_puts("AI_INPUT_BATCH8_PASS cases="); uart_putdec(cases); uart_putc('\n');
    return cases==24 ? 0 : 4;
#endif
}
