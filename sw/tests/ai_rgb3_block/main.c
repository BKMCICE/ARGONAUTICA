/* Actual production RGB3 control plus independent spatial CHW/Q24 oracle.
 * No production dispatch changes; prototype is diagnostic-only. */
#ifdef YOLO_HOST_TEST
#include <stdio.h>
#include "../ai_1x1_block_layer/host_mmio.h"
#endif
#define main a24_unused_production_main
#include "../../yolo_fixed/main.c"
#undef main
#include "rgb3_block.h"
#include "expected.h"
#ifdef YOLO_HOST_TEST
uint32_t host_ai_calls;
#else
volatile uint32_t a24_result;
void *memset(void *d,int v,__SIZE_TYPE__ n)
{
    volatile unsigned char *p=d;for(__SIZE_TYPE__ i=0;i<n;++i)p[i]=(unsigned char)v;return d;
}
#endif
#if A24_SHORT
#define IN_CAP 512
#define OUT_CAP 512
#else
#define IN_CAP 307200
#define OUT_CAP 204800
#endif
static int8_t input[IN_CAP+16],weights[27*13+16],actual[OUT_CAP+16],prior[OUT_CAP+16];
static int32_t params[26];
/* ih,iw,oh,ow,oc,stride,pad,leaky. k2 is the real layer0 geometry. */
static const uint32_t shapes[7][8]={
    {5,19,3,10,5,2,1,1},{3,7,3,7,9,1,1,0},{320,320,160,160,8,2,1,1},
    {7,13,5,11,7,1,0,1},{1,1,1,1,1,1,1,0},{5,17,2,8,3,2,0,1},
    {4,11,2,4,4,1,1,1}
};
static YoloLayer shape(uint32_t k)
{
    YoloLayer l={0};l.kind=YOLO_CONV;l.size=3;l.ic=3;l.groups=1;
    l.ih=shapes[k][0];l.iw=shapes[k][1];l.oh=shapes[k][2];l.ow=shapes[k][3];
    l.oc=shapes[k][4];l.stride=shapes[k][5];l.pad=shapes[k][6];l.leaky=shapes[k][7];return l;
}
static uint32_t hash(const void *p,uint32_t n)
{
    const uint8_t *x=p;uint32_t h=2166136261u;for(uint32_t i=0;i<n;++i)h=(h^x[i])*16777619u;return h;
}
static void prepare(uint32_t seed)
{
    for(uint32_t i=0;i<sizeof(input);++i)input[i]=seed==2?-128:(int8_t)(i*73u+seed*19u);
    for(uint32_t i=0;i<sizeof(weights);++i)weights[i]=seed==2?-128:(int8_t)(i*59u+seed*31u);
    for(uint32_t i=0;i<13;++i){params[2*i]=(i&1?-1:1)*(seed==2?256:16384+(int32_t)i*31);params[2*i+1]=(int32_t)(i%17)-8;}
    for(uint32_t i=0;i<sizeof(actual);++i)actual[i]=prior[i]=0x5a;
}
static int verify_output(const YoloLayer *l,uint32_t k,uint32_t seed)
{
    uint32_t n=l->oh*l->ow*l->oc;
    for(uint32_t i=0;i<sizeof(actual);++i){
        if(actual[i]!=prior[i])return 1;
        if((i<8||i>=8+n)&&actual[i]!=0x5a)return 2;
    }
    if(k<7&&hash(actual+8,n)!=a24_expected[seed-1][k])return 3;
    return 0;
}
#ifdef YOLO_HOST_TEST
static int32_t scalar_scale(int64_t v,int32_t m)
{
    int64_t p=v*m,n=((p<0?-p:p)+8388608)/16777216;return(int32_t)(p<0?-n:n);
}
static int oracle(const YoloLayer *l)
{
    for(uint32_t oc=0;oc<l->oc;++oc)for(uint32_t y=0;y<l->oh;++y)for(uint32_t x=0;x<l->ow;++x){
        int64_t dot=0;
        for(uint32_t c=0;c<3;++c)for(uint32_t ky=0;ky<3;++ky)for(uint32_t kx=0;kx<3;++kx){
            int yy=(int)(y*l->stride+ky)-(int)l->pad,xx=(int)(x*l->stride+kx)-(int)l->pad;
            if(yy>=0&&xx>=0&&(uint32_t)yy<l->ih&&(uint32_t)xx<l->iw)
                dot+=(int32_t)input[8+(c*l->ih+(uint32_t)yy)*l->iw+(uint32_t)xx]*weights[8+(oc*3+c)*9+ky*3+kx];
        }
        int32_t v=scalar_scale(dot,params[2*oc])+params[2*oc+1];
        if(l->leaky&&v<0)v=scalar_scale(v,1677722);
        if(v>127)v=127;
        if(v< -127)v=-127;
        if(actual[8+(oc*l->oh+y)*l->ow+x]!=v)return 1;
    }
    return 0;
}
#endif
static int guards(uint32_t *count)
{
    YoloLayer l=shape(0),v;prepare(1);*count=0;
    uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
    uint32_t ah=hash(actual,sizeof(actual)),bh=hash(prior,sizeof(prior)),lh=hash(&l,sizeof(l));
#ifdef YOLO_HOST_TEST
    a03_reset(0);
#endif
#define BAD(a,b,c,d,e) do{if(rgb3_block(a,b,c,d,e)!=AI_BLOCK_BAD_SHAPE)return 1;++*count;}while(0)
    BAD(0,input+8,actual+8,weights+8,params);
    BAD(&l,0,actual+8,weights+8,params);BAD(&l,input+8,0,weights+8,params);
    BAD(&l,input+8,actual+8,0,params);BAD(&l,input+8,actual+8,weights+8,0);
#define FIELD(n,x) do{v=l;v.n=x;BAD(&v,input+8,actual+8,weights+8,params);}while(0)
    FIELD(kind,2);FIELD(size,1);FIELD(ic,1);FIELD(groups,2);FIELD(oc,0);
    FIELD(ih,0);FIELD(iw,0);FIELD(oh,0);FIELD(ow,0);FIELD(stride,0);FIELD(stride,3);
    FIELD(pad,3);FIELD(ih,0x40000000u);FIELD(iw,0x40000000u);
    FIELD(oh,100);FIELD(ow,100);FIELD(oc,UINT32_MAX);
    v=l;v.ih=v.iw=65536;BAD(&v,input+8,actual+8,weights+8,params);
    BAD(&l,input+8,input+8,weights+8,params);BAD(&l,input+8,weights+8,weights+8,params);
    BAD(&l,input+8,(int8_t *)params,weights+8,params);BAD(&l,input+8,(int8_t *)&l,weights+8,params);
    BAD(&l,input+8,(int8_t *)(uintptr_t)(UINTPTR_MAX-3),weights+8,params);
#undef FIELD
#undef BAD
    if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph||
       hash(actual,sizeof(actual))!=ah||hash(prior,sizeof(prior))!=bh||hash(&l,sizeof(l))!=lh)return 3;
#ifdef YOLO_HOST_TEST
    if(a03_reads||a03_writes)return 2;
#endif
    return 0;
}
#ifdef YOLO_HOST_TEST
static int host_case(YoloLayer l,uint32_t k,uint32_t seed)
{
    prepare(seed);a03_reset(0);uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
    conv3x3_input3_prepacked(&l,input+8,prior+8,weights+8,params,l.oc);
    if(rgb3_block(&l,input+8,actual+8,weights+8,params)||oracle(&l)||verify_output(&l,k,seed))return 1;
    if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 2;
    if(a03_starts!=((l.oc+3)/4)*l.oh*((l.ow+7)/8)||a03_weight_words!=l.oc*9||a03_pixel_words!=((l.oc+3)/4)*l.oh*l.ow*9)return 3;
    return 0;
}
#else
static void cycles(const char *name,uint64_t value)
{
    uart_puts(name);uart_puts("=0x");uart_puthex((uint32_t)(value>>32));uart_puthex((uint32_t)value);
}
#endif
int main(void)
{
    uint32_t g=0,cases=0;
#ifndef YOLO_HOST_TEST
    uart_init(CLK_HZ,BAUD);AI_BIAS=0;
#endif
    if(guards(&g)||g!=28)return 10;
#ifdef YOLO_HOST_TEST
    for(uint32_t seed=1;seed<=3;++seed)for(uint32_t k=0;k<7;++k){if(host_case(shape(k),k,seed))return 20;++cases;}
    for(uint32_t k=0;k<360;++k){
        YoloLayer l=shape(0);l.ih=1+k%9;l.iw=1+(k*7)%21;l.pad=k%3;l.stride=1+(k/3)%2;
        if(l.ih+2*l.pad<3||l.iw+2*l.pad<3)continue;
        l.oh=(l.ih+2*l.pad-3)/l.stride+1;l.ow=(l.iw+2*l.pad-3)/l.stride+1;
        if(k%4==0){l.oh=1;l.ow=1;}
        l.oc=1+k%13;l.leaky=k%2;if(host_case(l,7,1+k%3))return 21;++cases;
    }
    for(uint32_t mode=1;mode<=6;++mode){YoloLayer l=shape(0);prepare(1);a03_reset(mode);
        int e=mode==1?AI_BLOCK_UNSUPPORTED:mode==3||mode==6?AI_BLOCK_TIMEOUT:AI_BLOCK_HW_ERROR;
        if(rgb3_block(&l,input+8,actual+8,weights+8,params)!=e)return 22;
    }
    printf("A24_HOST_ORACLE_PASS cases=%u guards=%u errors=6\n",cases,g);return 0;
#else
    uart_puts("A24_GUARDS_PASS count=");uart_putdec(g);uart_putc('\n');
    if(AI_BLOCK_READ(AI_BLOCK_REG_ID)!=AI_BLOCK_ID)return 90;
    for(uint32_t k=0;k<7;++k){
        if(A24_SHORT&&k==2)continue;
        YoloLayer l=shape(k);prepare(1);uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
        conv3x3_input3_prepacked(&l,input+8,prior+8,weights+8,params,l.oc);
        if(rgb3_block(&l,input+8,actual+8,weights+8,params)||verify_output(&l,k,1))return 30;
        for(uint32_t sample=0;sample<(A24_SHORT?1u:4u);++sample){uint64_t a,b,t;
            if(sample&1){
                t=rdcycle64();if(rgb3_block(&l,input+8,actual+8,weights+8,params))return 31;b=rdcycle64()-t;
                t=rdcycle64();conv3x3_input3_prepacked(&l,input+8,prior+8,weights+8,params,l.oc);a=rdcycle64()-t;
            }else{
                t=rdcycle64();conv3x3_input3_prepacked(&l,input+8,prior+8,weights+8,params,l.oc);a=rdcycle64()-t;
                t=rdcycle64();if(rgb3_block(&l,input+8,actual+8,weights+8,params))return 32;b=rdcycle64()-t;
            }
            if(verify_output(&l,k,1))return 33;
            uart_puts("A24_SAMPLE shape=");uart_putdec(k);uart_puts(" sample=");uart_putdec(sample);
            cycles(" control",a);cycles(" candidate",b);uart_putc('\n');++cases;
        }
        if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 34;
    }
    uart_puts("A24_DIAGNOSTIC_PASS samples=");uart_putdec(cases);uart_putc('\n');a24_result=1;return 0;
#endif
}
