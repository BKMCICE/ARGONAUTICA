/* Actual production control/candidate in separate TUs; all timing surrounds
 * complete operators, including validation, prepacking, transport and Q24.
 * Scalar reference uses independent CHW indexing and division-based rounding. */
#include "diag.h"
#include "../ai_pdata_reuse/expected.h"
#include "../ai_block8_post/expected_short.h"
#ifdef YOLO_HOST_TEST
#include <stdio.h>
#include "host_mmio.h"
uint32_t host_ai_calls;
#else
volatile uint32_t a48_result,a48_phase;
void *memset(void *d,int v,__SIZE_TYPE__ n)
{
    volatile unsigned char *p=d;
    for (__SIZE_TYPE__ i=0;i<n;++i) p[i]=(unsigned char)v;
    return d;
}
#endif
#include "../../common/ai_mac_block.h"
#if A50_SHORT
#define IN_CAP 4096
#define OUT_CAP 9216
#define W_CAP 32768
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
#if A50_SHORT
    if(k==2||k==3||k==8||k==9||k==10){l.ih=2;l.iw=17;}
#endif
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
#if A50_SHORT
    if(index<11&&hash(actual+8,n)!=a48_short_expected[index])return 3;
#else
    if(index<11&&hash(actual+8,n)!=a28_expected[seed-1][index])return 3;
#endif
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

#include "harness.inc"
