/* Independent lane and scalar-Q24 checks of the production DW3x3 path. */
#ifdef YOLO_HOST_TEST
#include <stdio.h>
#include "ai_mac.h"
uint32_t host_ai_calls;
static uint32_t check_packing, packing_failed, expected_pixels[3];
static int32_t checked_dot(uint32_t p0,uint32_t p1,uint32_t p2,
                           uint32_t w0,uint32_t w1,uint32_t w2)
{
    if(check_packing && (p0!=expected_pixels[0] || p1!=expected_pixels[1] || p2!=expected_pixels[2])) packing_failed=1;
    return ai_dot9_packed(p0,p1,p2,w0,w1,w2);
}
#define ai_dot9_packed checked_dot
#endif
#define main yolo_app_main
#include "../../yolo_fixed/main.c"
#undef main

static int8_t input[5*7*9+16], kernels[5*9], actual[5*7*9+16];
static int32_t params[10];
static int8_t sample(uint32_t index,uint32_t pattern)
{
    if(pattern==0) return (int8_t)((index*173u+71u)&255u);
    if(pattern==1) return -128;
    if(pattern==2) return 127;
    if(pattern==3) return (index&1u) ? -128 : 127;
    if(pattern==4) return (index&1u) ? 0 : -1;
    return 0;
}
static int32_t reference_scale(int64_t value,int32_t multiplier)
{
    int64_t product=value*multiplier;
    int64_t rounded=((product<0?-product:product)+8388608)/16777216;
    return (int32_t)(product<0?-rounded:rounded);
}

int main(void)
{
#ifdef YOLO_HOST_TEST
    const uint32_t heights[]={1,2,3,5,7},widths[]={1,2,3,7,9},channels[]={1,2,5};
#else
    const uint32_t heights[]={1,2,5},widths[]={1,3,7},channels[]={1,2};
    AI_BIAS=0;
#endif
    uint32_t dots=0,convs=0,interior=0;
    for(uint32_t hi=0;hi<sizeof(heights)/sizeof(heights[0]);++hi)
    for(uint32_t wi=0;wi<sizeof(widths)/sizeof(widths[0]);++wi)
    for(uint32_t pattern=0;pattern<6;++pattern) {
        uint32_t h=heights[hi],w=widths[wi];
        for(uint32_t i=0;i<sizeof(input);++i) input[i]=0x5a;
        for(uint32_t i=0;i<h*w;++i) input[8+i]=sample(i,pattern);
        for(uint32_t i=0;i<9;++i) kernels[i]=sample(i,pattern==1?2:(pattern==2?1:pattern));
        (void)ai_dot9_packed(0xffffffffu,0xffffffffu,0xffffffffu,0xdeadbeefu,0x89abcdefu,0x55u);
        ai_load_1x1_weights(kernels,9);
        uint32_t resident[3];
        for(uint32_t j=0;j<3;++j) resident[j]=0;
        for(uint32_t i=0;i<9;++i) resident[i/4]|=(uint32_t)(uint8_t)kernels[i]<<((i%4)*8);
        for(uint32_t stride=1;stride<=2;++stride)
        for(int32_t top=-2;top<=(int32_t)h;top+=(int32_t)stride)
        for(int32_t left=-2;left<=(int32_t)w;left+=(int32_t)stride) {
            int64_t expected=0;
            uint32_t packed[3]={0,0,0};
            for(int32_t ky=0;ky<3;++ky) for(int32_t kx=0;kx<3;++kx) {
                int32_t y=top+ky,x=left+kx;
                uint32_t lane=(uint32_t)(ky*3+kx);
                if(y>=0 && y<(int32_t)h && x>=0 && x<(int32_t)w) {
                    int8_t value=input[8+(uint32_t)y*w+(uint32_t)x];
                    expected+=(int32_t)value*kernels[lane];
                    packed[lane/4]|=(uint32_t)(uint8_t)value<<((lane%4)*8);
                }
            }
#ifdef YOLO_HOST_TEST
            for(uint32_t j=0;j<3;++j) expected_pixels[j]=packed[j];
            check_packing=1;
#endif
            if(ai_dot3x3_loaded(input+8,h,w,top,left)!=expected) return 1;
#ifdef YOLO_HOST_TEST
            check_packing=0;
            if(packing_failed) return 2;
            for(uint32_t j=0;j<3;++j) if(host_resident_weights[j]!=resident[j]) return 3;
#else
            if(AI_PIX0!=packed[0] || AI_PIX1!=packed[1] || AI_PIX2!=packed[2]) return 2;
            if(AI_WGT0!=resident[0] || AI_WGT1!=resident[1] || AI_WGT2!=resident[2]) return 3;
#endif
            if(top>=0 && left>=0 && top+2<(int32_t)h && left+2<(int32_t)w) ++interior;
            ++dots;
        }
        for(uint32_t i=0;i<sizeof(input);++i) if((i<8 || i>=8+h*w) && input[i]!=0x5a) return 4;
    }
    for(uint32_t hi=0;hi<sizeof(heights)/sizeof(heights[0]);++hi)
    for(uint32_t wi=0;wi<sizeof(widths)/sizeof(widths[0]);++wi)
    for(uint32_t ci=0;ci<sizeof(channels)/sizeof(channels[0]);++ci)
    for(uint32_t stride=1;stride<=2;++stride)
    for(uint32_t pad=0;pad<=1;++pad)
    for(uint32_t leaky=0;leaky<=1;++leaky)
    for(uint32_t pattern=0;pattern<6;++pattern) {
        uint32_t h=heights[hi],w=widths[wi],c=channels[ci];
        if(h+2*pad<3 || w+2*pad<3) continue;
        YoloLayer layer;
        layer.kind=YOLO_CONV;layer.ih=h;layer.iw=w;layer.ic=c;
        layer.oh=(h+2*pad-3)/stride+1;layer.ow=(w+2*pad-3)/stride+1;
        layer.oc=c;layer.groups=c;layer.size=3;layer.stride=stride;layer.pad=pad;layer.leaky=leaky;
        for(uint32_t i=0;i<sizeof(input);++i) input[i]=0x5a;
        for(uint32_t i=0;i<c*h*w;++i) input[8+i]=sample(i,pattern);
        for(uint32_t i=0;i<c*9;++i) kernels[i]=sample(i,pattern==1?2:(pattern==2?1:pattern));
        for(uint32_t i=0;i<c;++i) {
            params[2*i]=((i&1u)?-1:1)*((1<<14)+(int32_t)pattern*3989);
            params[2*i+1]=(int32_t)i*17-29;
        }
        for(uint32_t i=0;i<sizeof(actual);++i) actual[i]=0x5a;
        (void)ai_dot9_packed(0xffffffffu,0xffffffffu,0xffffffffu,0xdeadbeefu,0x89abcdefu,0x55u);
        conv3x3_depthwise_reuse(&layer,input+8,actual+8,kernels,params);
        for(uint32_t oc=0;oc<c;++oc) for(uint32_t oy=0;oy<layer.oh;++oy)
        for(uint32_t ox=0;ox<layer.ow;++ox) {
            int64_t sum=0;
            for(int32_t ky=0;ky<3;++ky) for(int32_t kx=0;kx<3;++kx) {
                int32_t y=(int32_t)(oy*stride)+ky-(int32_t)pad;
                int32_t x=(int32_t)(ox*stride)+kx-(int32_t)pad;
                if(y>=0 && y<(int32_t)h && x>=0 && x<(int32_t)w)
                    sum+=(int32_t)input[8+(oc*h+(uint32_t)y)*w+(uint32_t)x]*kernels[oc*9+(uint32_t)ky*3+(uint32_t)kx];
            }
            int32_t value=reference_scale(sum,params[oc*2])+params[oc*2+1];
            if(leaky && value<0) value=reference_scale(value,1677722);
            if(value>127) value=127;
            if(value< -127) value= -127;
            if(actual[8+(oc*layer.oh+oy)*layer.ow+ox]!=value) return 5;
        }
        for(uint32_t i=0;i<sizeof(actual);++i) if((i<8 || i>=8+c*layer.oh*layer.ow) && actual[i]!=0x5a) return 6;
        for(uint32_t i=0;i<sizeof(input);++i) if((i<8 || i>=8+c*h*w) && input[i]!=0x5a) return 7;
        ++convs;
    }
#ifdef YOLO_HOST_TEST
    printf("AI_DW3X3_INTERIOR_PASS dots=%u convs=%u interior=%u\n",dots,convs,interior);
#else
    uart_puts("AI_DW3X3_INTERIOR_PASS dots=");uart_putdec(dots);
    uart_puts(" convs=");uart_putdec(convs);
    uart_puts(" interior=");uart_putdec(interior);uart_putc('\n');
#endif
    return 0;
}
