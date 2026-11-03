/* Actual production control/candidate in separate TUs; all timing surrounds
 * complete operators, including validation, prepacking, transport and Q24.
 * Scalar reference uses independent CHW indexing and division-based rounding. */
#include "diag.h"
#include "expected.h"
#ifdef YOLO_HOST_TEST
#include <stdio.h>
#include "../ai_1x1_block_layer/host_mmio.h"
uint32_t host_ai_calls;
#else
volatile uint32_t a28_result;
void *memset(void *d,int v,__SIZE_TYPE__ n)
{
    volatile unsigned char *p=d;
    for (__SIZE_TYPE__ i=0;i<n;++i) p[i]=(unsigned char)v;
    return d;
}
#endif
#include "../../common/ai_mac_block.h"
#if A28_SHORT
#define IN_CAP 512
#define OUT_CAP 512
#define W_CAP 512
#else
#define IN_CAP 204800
#define OUT_CAP 614400
#define W_CAP 57120
#endif
static int8_t input[IN_CAP+16],weights[W_CAP+16],actual[OUT_CAP+16],prior[OUT_CAP+16];
static int32_t params[510];
/* ih, iw, ic, oc, groups, stride, leaky; large shapes match A18/A19 hotspots. */
static const uint32_t shapes[11][7]={
    {2,9,10,5,1,1,1},{3,7,17,9,1,1,1},
    {20,20,120,255,1,1,1},{40,40,16,96,1,1,1},
    {5,19,18,10,2,2,0},{1,1,224,7,1,1,1},
    {3,11,1,1,1,1,0},{3,17,9,8,1,1,1},
    {160,160,4,24,1,1,1},{160,160,8,8,1,1,1},{20,20,120,120,1,1,1}
};
static uint32_t hash(const void *buf,uint32_t n)
{
    const uint8_t *p=buf;uint32_t h=2166136261u;
    for(uint32_t i=0;i<n;++i)h=(h^p[i])*16777619u;
    return h;
}
static YoloLayer shape(unsigned k)
{
    YoloLayer l={0};l.kind=YOLO_CONV;l.size=1;
    l.ih=shapes[k][0];l.iw=shapes[k][1];l.ic=shapes[k][2];l.oc=shapes[k][3];
    l.groups=shapes[k][4];l.stride=shapes[k][5];l.leaky=shapes[k][6];
    l.oh=(l.ih-1)/l.stride+1;l.ow=(l.iw-1)/l.stride+1;return l;
}
static void prepare(unsigned seed)
{
    for(unsigned i=0;i<sizeof(input);++i)input[i]=(int8_t)(i*73u+seed*19u);
    for(unsigned i=0;i<sizeof(weights);++i)weights[i]=(int8_t)(i*59u+seed*31u);
    for(unsigned i=0;i<255;++i){params[2*i]=(i&1?-1:1)*(16384+(int32_t)i*29);params[2*i+1]=(int32_t)(i%17)-8;}
    for(unsigned i=0;i<sizeof(actual);++i)actual[i]=prior[i]=0x5a;
}
static int check(const YoloLayer *l,unsigned index,unsigned seed)
{
    uint32_t n=l->oc*l->oh*l->ow;
    for(uint32_t i=0;i<sizeof(actual);++i){
        if(actual[i]!=prior[i])return 1;
        if((i<8||i>=8+n)&&actual[i]!=0x5a)return 2;
    }
    if(index<11&&hash(actual+8,n)!=a28_expected[seed-1][index])return 3;
    return 0;
}
static int32_t scale(int64_t dot,int32_t m)
{
    int64_t p=dot*m,n=((p<0?-p:p)+8388608)/16777216;
    return(int32_t)(p<0?-n:n);
}
static int8_t quantize(int32_t dot,int32_t m,int32_t bias,unsigned leaky)
{
    int32_t v=scale(dot,m)+bias;
    if(leaky&&v<0)v=scale(v,1677722);
    if(v>127)v=127;
    if(v< -127)v=-127;
    return(int8_t)v;
}
static int store_tests(unsigned *cases)
{
    const int32_t values[]={-1048576,-255,-254,-253,-129,-128,-127,-3,-1,0,1,3,126,127,128,254,255,1048576};
    const int32_t mult[]={-16777216,-8388608,-16384,0,16384,8388608,16777216};
    const int32_t bias[]={-128,-1,0,1,127};
    int32_t a[8];int8_t d[24];
    *cases=0;
    for(unsigned v=0;v<18;++v)for(unsigned m=0;m<7;++m)for(unsigned b=0;b<5;++b)
    for(unsigned leaky=0;leaky<2;++leaky)for(unsigned n=1;n<=8;++n){
        for(unsigned i=0;i<8;++i)a[i]=values[(v+i)%18];
        for(unsigned i=0;i<24;++i)d[i]=0x5a;
        a28_store(a,d+8,n,mult[m],bias[b],leaky);
        for(unsigned i=0;i<24;++i){
            int8_t expected=i>=8&&i<8+n?quantize(a[i-8],mult[m],bias[b],leaky):0x5a;
            if(d[i]!=expected)return 1;
        }
        ++*cases;
    }
    return 0;
}
static int alias_tests(void)
{
    YoloLayer l=shape(0);prepare(1);
    /* Every rejection must precede MMIO and leave the full backing objects intact. */
    uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
    if(a28_candidate(&l,input+8,input+8,weights+8,params)!=AI_BLOCK_BAD_SHAPE)return 1;
    if(a28_candidate(&l,input+8,weights+8,weights+8,params)!=AI_BLOCK_BAD_SHAPE)return 2;
    if(a28_candidate(&l,input+8,(int8_t *)params,weights+8,params)!=AI_BLOCK_BAD_SHAPE)return 3;
    if(a28_candidate(&l,input+8,(int8_t *)&l,weights+8,params)!=AI_BLOCK_BAD_SHAPE)return 4;
    if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 5;
    return 0;
}
#ifdef YOLO_HOST_TEST
static int oracle(const YoloLayer *l)
{
    uint32_t plane=l->ih*l->iw,op=l->oh*l->ow,ci=l->ic/l->groups,co=l->oc/l->groups;
    for(uint32_t oc=0;oc<l->oc;++oc)for(uint32_t y=0;y<l->oh;++y)for(uint32_t x=0;x<l->ow;++x){
        int64_t dot=0;
        for(uint32_t c=0;c<ci;++c)
            dot+=(int32_t)input[8+((oc/co)*ci+c)*plane+y*l->stride*l->iw+x*l->stride]*weights[8+oc*ci+c];
        if(actual[8+oc*op+y*l->ow+x]!=quantize((int32_t)dot,params[2*oc],params[2*oc+1],l->leaky))return 1;
    }
    return 0;
}
extern void *a28_scratch(unsigned);
static int host_guards(void)
{
    YoloLayer l=shape(0),v;prepare(1);a03_reset(0);
    uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
#define REJECT(a,b,c,d,e) do { if(a28_candidate(a,b,c,d,e)!=AI_BLOCK_BAD_SHAPE)return 1; } while(0)
    REJECT(0,input+8,actual+8,weights+8,params);
    REJECT(&l,0,actual+8,weights+8,params);REJECT(&l,input+8,0,weights+8,params);
    REJECT(&l,input+8,actual+8,0,params);REJECT(&l,input+8,actual+8,weights+8,0);
#define FIELD(n,x) do{v=l;v.n=x;REJECT(&v,input+8,actual+8,weights+8,params);}while(0)
    FIELD(kind,2);FIELD(size,3);FIELD(groups,0);FIELD(groups,3);FIELD(stride,0);FIELD(pad,1);
    FIELD(ih,0);FIELD(iw,0);FIELD(oh,0);FIELD(ow,0);FIELD(oc,0);FIELD(ic,0);
    FIELD(ic,225);FIELD(oc,256);FIELD(ow,10);FIELD(oh,3);FIELD(ih,UINT32_MAX);
    v=l;v.ih=v.oh=256;v.iw=v.ow=256;REJECT(&v,input+8,actual+8,weights+8,params);
    v=l;v.ih=v.oh=UINT32_MAX;v.iw=v.ow=1;REJECT(&v,input+8,actual+8,weights+8,params);
    for(unsigned i=0;i<2;++i){
        void *p=a28_scratch(i);
        REJECT(&l,p,actual+8,weights+8,params);REJECT(&l,input+8,p,weights+8,params);
        REJECT(&l,input+8,actual+8,p,params);REJECT(&l,input+8,actual+8,weights+8,p);
    }
    if(a03_reads||a03_writes||hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 2;
    /* Valid cropped stride-two geometry, independently checked below. */
    return 0;
#undef FIELD
#undef REJECT
}
static int host_case(YoloLayer l,unsigned k,unsigned seed)
{
    prepare(seed);a03_reset(0);
    uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
    if(a28_control(&l,input+8,prior+8,weights+8,params))return 1;
    uint32_t control_tasks=a03_starts, control_weights=a03_weight_words, control_pixels=a03_pixel_words;
    a03_reset(0);
    if(a28_candidate(&l,input+8,actual+8,weights+8,params))return 1;
    if(oracle(&l)||check(&l,k,seed))return 2;
    if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 3;
    uint32_t ci=l.ic/l.groups,co=l.oc/l.groups,b=(ci+8)/9,tiles=l.oh*((l.ow+7)/8),op=l.oh*l.ow;
    uint32_t tasks=l.groups*((co+3)/4)*tiles;
    if(a03_starts!=tasks || control_tasks!=tasks ||
       control_weights!=l.groups*co*b*3 ||
       control_pixels!=l.groups*((co+3)/4)*op*b*3 ||
       a03_weight_words!=l.groups*tiles*co*b*3 ||
       a03_pixel_words!=l.groups*op*b*3)return 4;
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
    unsigned stores=0,cases=0;
#ifndef YOLO_HOST_TEST
    uart_init(CLK_HZ,BAUD);if(AI_BLOCK_READ(AI_BLOCK_REG_ID)!=AI_BLOCK_ID)return 90;AI_BIAS=0;
#else
    a03_reset(0);
#endif
    if(store_tests(&stores)||stores!=10080)return 10;
    if(alias_tests())return 11;
#ifdef YOLO_HOST_TEST
    if(a03_reads||a03_writes)return 12;
    for(unsigned seed=1;seed<=2;++seed)for(unsigned k=0;k<11;++k){
        if(host_case(shape(k),k,seed))return 20;
        ++cases;
    }
    for(unsigned k=0;k<144;++k){
        YoloLayer l=shape(0);l.groups=1+k%2;l.stride=1+(k/2)%2;
        l.ih=1+k%5;l.iw=1+(k*7)%19;l.oh=(l.ih-1)/l.stride+1;l.ow=(l.iw-1)/l.stride+1;
        const unsigned ci[]={1,8,9,10,16,17,224};l.ic=ci[k%7]*l.groups;
        l.oc=(1+(k*3)%11)*l.groups;l.leaky=k%2;
        if(host_case(l,11,1+k%2))return 21;
        ++cases;
    }
    YoloLayer crop=shape(4);crop.oh=2;crop.ow=3;
    if(host_case(crop,11,1))return 27;++cases;
    for(unsigned mode=1;mode<=6;++mode){YoloLayer l=shape(0);prepare(1);a03_reset(mode);
        int expected=mode==1?AI_BLOCK_UNSUPPORTED:mode==3||mode==6?AI_BLOCK_TIMEOUT:AI_BLOCK_HW_ERROR;
        if(a28_candidate(&l,input+8,actual+8,weights+8,params)!=expected)return 22;
        uint32_t n=l.oc*l.oh*l.ow;
        if(mode==6){
            if(a03_starts!=2)return 23;
            /* First batch wrote only channels 0..3, pixels 0..7. No later
             * fallback or writes are allowed after second-task timeout. */
            for(uint32_t i=0;i<sizeof(actual);++i){
                int changed=i>=8&&i<8+n&&(i-8)/(l.oh*l.ow)<4&&(i-8)%(l.oh*l.ow)<8;
                if(!changed&&actual[i]!=0x5a)return 24;
                if(changed){
                    uint32_t ch=(i-8)/(l.oh*l.ow),px=(i-8)%(l.oh*l.ow);
                    int32_t dot=0;
                    for(uint32_t c=0;c<l.ic;++c)
                        dot+=(int32_t)input[8+c*l.ih*l.iw+px]*weights[8+ch*l.ic+c];
                    if(actual[i]!=quantize(dot,params[2*ch],params[2*ch+1],l.leaky))return 28;
                }
            }
        }else for(uint32_t i=0;i<sizeof(actual);++i)if(actual[i]!=0x5a)return 25;
    }
    if(host_guards())return 26;
    printf("A28_HOST_ORACLE_PASS operators=%u stores=%u aliases=4 errors=6 counters=PASS guards=PASS\n",cases,stores);return 0;
#else
    uart_puts("A28_STORE_PASS cases=");uart_putdec(stores);uart_puts(" aliases=4\n");
    for(unsigned k=0;k<(A28_SHORT?2u:11u);++k){
        YoloLayer l=shape(k);prepare(1);
        uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
        if(a28_control(&l,input+8,prior+8,weights+8,params)||a28_candidate(&l,input+8,actual+8,weights+8,params)||check(&l,k,1))return 30;
        for(unsigned sample=0;sample<(A28_SHORT?1u:4u);++sample){uint64_t a,b,t;
            if(sample&1){
                t=rdcycle64();if(a28_candidate(&l,input+8,actual+8,weights+8,params))return 31;b=rdcycle64()-t;
                t=rdcycle64();if(a28_control(&l,input+8,prior+8,weights+8,params))return 32;a=rdcycle64()-t;
            }else{
                t=rdcycle64();if(a28_control(&l,input+8,prior+8,weights+8,params))return 33;a=rdcycle64()-t;
                t=rdcycle64();if(a28_candidate(&l,input+8,actual+8,weights+8,params))return 34;b=rdcycle64()-t;
            }
            if(check(&l,k,1))return 35;
            uart_puts("A28_SAMPLE shape=");uart_putdec(k);uart_puts(" sample=");uart_putdec(sample);
            cycles(" control",a);cycles(" candidate",b);uart_putc('\n');++cases;
        }
        if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 36;
    }
    uart_puts("A28_DIAGNOSTIC_PASS samples=");uart_putdec(cases);uart_putc('\n');a28_result=1;return 0;
#endif
}
