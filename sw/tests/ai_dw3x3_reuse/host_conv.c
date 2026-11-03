/* Differential test with an independent scalar convolution and Q24 rounding. */
#include <stdio.h>
#include <string.h>
#define main yolo_app_main
#include "../../yolo_fixed/main.c"
#undef main
uint32_t host_ai_calls;

static int32_t reference_scale(int64_t value,int32_t multiplier)
{
    int64_t product=value*multiplier;
    int64_t rounded=((product<0?-product:product)+8388608)/16777216;
    return (int32_t)(product<0?-rounded:rounded);
}

int main(void)
{
    const uint32_t heights[3]={1,2,5},widths[3]={1,3,7},channels[3]={1,2,5};
    int8_t input[5*5*7],kernels[5*9],actual[5*5*7+16];
    int32_t params[10];
    uint32_t cases=0;
    for(uint32_t hi=0;hi<3;++hi) for(uint32_t wi=0;wi<3;++wi)
    for(uint32_t ci=0;ci<3;++ci) for(uint32_t stride=1;stride<=2;++stride)
    for(uint32_t pad=0;pad<=1;++pad) for(uint32_t leaky=0;leaky<=1;++leaky) {
        uint32_t h=heights[hi],w=widths[wi],c=channels[ci];
        if(h+2*pad<3 || w+2*pad<3) continue;
        YoloLayer layer={0};
        layer.kind=YOLO_CONV; layer.ih=h; layer.iw=w; layer.ic=c;
        layer.oh=(h+2*pad-3)/stride+1; layer.ow=(w+2*pad-3)/stride+1;
        layer.oc=c; layer.groups=c; layer.size=3; layer.stride=stride;
        layer.pad=pad; layer.leaky=leaky;
        for(unsigned i=0;i<sizeof(input);++i) input[i]=(int8_t)((i*173u+cases*71u)&255u);
        for(unsigned i=0;i<sizeof(kernels);++i) kernels[i]=(int8_t)((i*59u+cases*127u)&255u);
        for(unsigned i=0;i<5;++i) {
            params[2*i]=(i&1u) ? -(1<<18) : (1<<19)+(int32_t)i*3989;
            params[2*i+1]=(int32_t)i*37-111;
        }
        memset(actual,0x5a,sizeof(actual));
        conv3x3_depthwise_reuse(&layer,input,actual,kernels,params);
        for(uint32_t oc=0;oc<c;++oc) for(uint32_t y=0;y<layer.oh;++y)
        for(uint32_t x=0;x<layer.ow;++x) {
            int64_t sum=0;
            for(int32_t ky=0;ky<3;++ky) for(int32_t kx=0;kx<3;++kx) {
                int32_t iy=(int32_t)(y*stride+ky)-(int32_t)pad;
                int32_t ix=(int32_t)(x*stride+kx)-(int32_t)pad;
                if(iy>=0 && iy<(int32_t)h && ix>=0 && ix<(int32_t)w)
                    sum+=(int32_t)input[(oc*h+iy)*w+ix]*kernels[oc*9+ky*3+kx];
            }
            int32_t expected=reference_scale(sum,params[oc*2])+params[oc*2+1];
            if(leaky && expected<0) expected=reference_scale(expected,YOLO_LEAKY_Q24);
            if(expected>127) expected=127;
            if(expected< -127) expected= -127;
            if(actual[(oc*layer.oh+y)*layer.ow+x]!=expected) {
                printf("DW3X3_CONV_FAIL case=%u oc=%u y=%u x=%u\n",cases,oc,y,x); return 1;
            }
        }
        for(unsigned i=c*layer.oh*layer.ow;i<sizeof(actual);++i) if(actual[i]!=0x5a) return 2;
        ++cases;
    }
    printf("DW3X3_CONV_SCALAR_PASS cases=%u\n",cases);
    return cases==132 ? 0 : 3;
}
