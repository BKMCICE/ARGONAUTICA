/* Exercise the production convolution against an independent scalar oracle. */
#ifdef YOLO_HOST_TEST
#include <stdio.h>
#endif
#define main yolo_app_main
#include "../../yolo_fixed/main.c"
#undef main

#ifdef YOLO_HOST_TEST
uint32_t host_ai_calls;
#define TEST_CASES 1944u
#define OUTPUT_BYTES 4096
#else
#define TEST_CASES 36u
#define OUTPUT_BYTES 2048
#endif
static int8_t input[1024], kernels[512], actual[OUTPUT_BYTES];
static int32_t params[32];
static const uint32_t shapes[][2]={{1,1},{1,4},{2,2},{3,5},{5,3},{8,9}};

static uint32_t digest(const void *data, uint32_t bytes)
{
    const uint8_t *p=data;
    uint32_t h=2166136261u;
    for(uint32_t i=0;i<bytes;++i) h=(h^p[i])*16777619u;
    return h;
}

static int32_t scale_reference(int64_t value, int32_t multiplier)
{
    int64_t p=value*multiplier;
    int64_t q=((p<0 ? -p:p)+8388608)/16777216;
    return (int32_t)(p<0 ? -q:q);
}

static int check(const YoloLayer *l, const int8_t *weights, const int32_t *q)
{
    uint32_t ci=l->ic/l->groups,co=l->oc/l->groups;
    for(uint32_t oc=0;oc<l->oc;++oc)
    for(uint32_t y=0;y<l->oh;++y)
    for(uint32_t x=0;x<l->ow;++x) {
        int64_t sum=0;
        for(uint32_t c=0;c<ci;++c)
        for(uint32_t ky=0;ky<l->size;++ky)
        for(uint32_t kx=0;kx<l->size;++kx) {
            int32_t iy=(int32_t)(y*l->stride+ky)-(int32_t)l->pad;
            int32_t ix=(int32_t)(x*l->stride+kx)-(int32_t)l->pad;
            if(iy<0 || ix<0 || iy>=(int32_t)l->ih || ix>=(int32_t)l->iw) continue;
            uint32_t a=(((oc/co)*ci+c)*l->ih+(uint32_t)iy)*l->iw+(uint32_t)ix;
            uint32_t b=((oc*ci+c)*l->size+ky)*l->size+kx;
            sum+=(int32_t)input[a]*(int32_t)weights[b];
        }
        int32_t value=scale_reference(sum,q[oc*2])+q[oc*2+1];
        if(l->leaky && value<0) value=scale_reference(value,1677722);
        if(value>127) value=127;
        if(value< -127) value= -127;
        if(actual[8+(oc*l->oh+y)*l->ow+x]!=value) return 1;
    }
    for(uint32_t i=0;i<sizeof(actual);++i)
        if((i<8 || i>=8+l->oc*l->oh*l->ow) && actual[i]!=0x5a) return 2;
    return 0;
}

int main(void)
{
    uint32_t cases=0,starts=0;
#ifdef YOLO_HOST_TEST
    uint32_t dispatch_cases=0;
#endif
#ifndef YOLO_HOST_TEST
    AI_BIAS=0;
#endif
    for(uint32_t id=0;id<TEST_CASES;++id) {
        uint32_t shape,stride,pad,groups,co,pattern;
#ifdef YOLO_HOST_TEST
        uint32_t n=id;
        shape=n%6;n/=6;stride=1+n%2;n/=2;pad=n%3;n/=3;
        groups=1+n%3;n/=3;co=1+2*(n%3);n/=3;pattern=n%6;
#else
        shape=id%4+2;stride=1+((id/2)&1);pad=(id/4)%3;
        groups=1+(id&1);co=1+2*(id/12);pattern=(id/4)%6;
#endif
        YoloLayer l;
        l.kind=YOLO_CONV;l.size=3;l.stride=stride;l.pad=pad;
        l.ih=shapes[shape][0];l.iw=shapes[shape][1];
        l.oh=l.ih+2*pad>=3 ? (l.ih+2*pad-3)/stride+1:0;
        l.ow=l.iw+2*pad>=3 ? (l.iw+2*pad-3)/stride+1:0;
        l.ic=3*groups;l.oc=co*groups;l.groups=groups;l.leaky=id&1;
        if(l.ic*l.ih*l.iw>sizeof(input) || l.oc*27>sizeof(kernels) || 16+l.oc*l.oh*l.ow>sizeof(actual)) return 9;
        for(uint32_t i=0;i<sizeof(input);++i)
            input[i]=pattern==0 ? -128:pattern==1 ? 127:pattern==2 ? 0:pattern==3 ? (i&1 ? -128:127):(int8_t)(i*173u+id*71u);
        for(uint32_t i=0;i<sizeof(kernels);++i)
            kernels[i]=pattern<2 ? -128:pattern==2 ? 127:(int8_t)(i*59u+id*127u);
        for(uint32_t i=0;i<16;++i) {
            const int32_t mult[]={1,256,4096,65536,8388608,-4096};
            params[i*2]=mult[i%6];params[i*2+1]=(int32_t)i*19-90;
        }
        for(uint32_t i=0;i<sizeof(actual);++i) actual[i]=0x5a;
        if(ai_dot9_packed(0,0,0,0xdeadbeef,0x89abcdef,0x55)!=0) return 3;
        uint32_t ih=digest(input,sizeof(input)),wh=digest(kernels,sizeof(kernels)),qh=digest(params,sizeof(params));
#ifdef YOLO_HOST_TEST
        uint32_t before=host_ai_calls;
#endif
        conv3x3_input3_prepacked(&l,input,actual+8,kernels,params,co);
        uint32_t dots=3*l.oc*l.oh*l.ow;
#ifdef YOLO_HOST_TEST
        if(host_ai_calls-before!=dots) return 4;
#endif
        if(digest(input,sizeof(input))!=ih || digest(kernels,sizeof(kernels))!=wh || digest(params,sizeof(params))!=qh) return 5;
        if(check(&l,kernels,params)) {
#ifdef YOLO_HOST_TEST
            printf("AI_INPUT3_FAIL case=%u\n",id);
#endif
            return 6;
        }
        starts+=dots+1;++cases;
    }
    /* Zero output channels must not touch null input/weights/output/params. */
    YoloLayer empty;
    empty.ih=empty.iw=empty.oc=0;
    conv3x3_input3_prepacked(&empty,0,0,0,0,1);
#ifdef YOLO_HOST_TEST
    /* Test the actual production selector and all existing fallback families,
     * using model-owned weights/params with an independent scalar reference. */
    for(uint32_t k=1;k<=5;k+=2)
    for(uint32_t ci=1;ci<=4;++ci)
    for(uint32_t groups=1;groups<=2;++groups)
    for(uint32_t co=1;co<=3;co+=2) {
        YoloLayer l;
        l.weight_offset=l.param_offset=0;
        l.kind=YOLO_CONV;l.size=k;l.stride=1;l.pad=k/2;
        l.ih=l.oh=3;l.iw=l.ow=5;l.ic=ci*groups;l.oc=co*groups;l.groups=groups;l.leaky=1;
        for(uint32_t i=0;i<sizeof(input);++i) input[i]=(int8_t)(i*71u+ci*33u);
        for(uint32_t i=0;i<sizeof(actual);++i) actual[i]=0x5a;
        uint32_t h=digest(input,sizeof(input));
#if YOLO_1X1_ACC32
        if(!conv_layer(&l,input,actual+8)) return 7;
#else
        conv_layer(&l,input,actual+8);
#endif
        if(digest(input,sizeof(input))!=h || check(&l,yolo_weights,yolo_params_q24)) return 8;
        ++dispatch_cases;
    }
    printf("AI_INPUT3_PASS cases=%u dispatch=%u diagnostic_starts=%u zero_oc=PASS\n",cases,dispatch_cases,starts);
#else
    uart_puts("AI_INPUT3_PASS cases=");uart_putdec(cases);
    uart_puts(" starts=");uart_putdec(starts);uart_puts(" zero_oc=PASS\n");
#endif
    return 0;
}
