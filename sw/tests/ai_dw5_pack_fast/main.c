#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
#include "expected.h"
int a74_control(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a74_candidate(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
volatile uint32_t a74_result,a74_phase;
#ifndef A74_FULL
#define A74_FULL 0
#endif
#if A74_FULL
#define CAP 48000
#define SHAPES 2
#else
#define CAP 8192
#define SHAPES 8
#endif
static int8_t input[CAP+16],output[CAP+16],weights[128*25+16];
static int32_t params[256];
void *memset(void *d,int v,__SIZE_TYPE__ n){unsigned char *p=d;for(__SIZE_TYPE__ i=0;i<n;++i)p[i]=(unsigned char)v;return d;}
static const uint32_t geometries[8][7]={
 {3,9,120,1,2,1,0},{5,17,3,1,2,1,0},{7,19,3,2,2,0,0},{1,1,2,1,2,1,0},
 {3,3,2,1,4,0,1},{8,10,4,1,0,1,0},{3,8,1,1,2,0,0},{2,7,2,3,2,1,0}};
static YoloLayer shape(unsigned k){
    YoloLayer l={0};l.kind=YOLO_CONV;l.size=5;
#if A74_FULL
    l.ih=l.iw=k?10:20;l.ic=l.oc=l.groups=k?96:120;l.stride=1;l.pad=2;l.leaky=1;
#else
    l.ih=geometries[k][0];l.iw=geometries[k][1];l.ic=l.oc=l.groups=geometries[k][2];l.stride=geometries[k][3];l.pad=geometries[k][4];l.leaky=geometries[k][5];
#endif
    l.oh=(l.ih+2*l.pad-5)/l.stride+1;l.ow=(l.iw+2*l.pad-5)/l.stride+1;
#if !A74_FULL
    if(geometries[k][6]){--l.oh;--l.ow;}
#endif
    return l;
}
static uint32_t hash(const void *p,uint32_t n){const uint8_t *x=p;uint32_t h=2166136261u;for(uint32_t i=0;i<n;++i)h=(h^x[i])*16777619u;return h;}
static void prepare(void){
    for(unsigned i=0;i<sizeof(input);++i)input[i]=(int8_t)(i*73u+19u);
    for(unsigned i=0;i<sizeof(weights);++i)weights[i]=(int8_t)(i*59u+31u);
    for(unsigned i=0;i<128;++i){params[i*2]=(i&1?-1:1)*(16384+(int32_t)i*29);params[i*2+1]=(int32_t)(i%17)-8;}
}
static void field(const char *name,uint64_t n){uart_puts(name);uart_puts("=0x");uart_puthex((uint32_t)(n>>32));uart_puthex((uint32_t)n);}
static int run(unsigned k,unsigned phase,uint64_t *elapsed){
    YoloLayer l=shape(k);uint32_t n=l.oc*l.oh*l.ow;
    for(unsigned i=0;i<sizeof(output);++i)output[i]=0x5a;
    a74_phase=phase;uint64_t start=rdcycle64();
    int rc=phase==1?a74_control(&l,input+8,output+8,weights+8,params):a74_candidate(&l,input+8,output+8,weights+8,params);
    *elapsed=rdcycle64()-start;a74_phase=0;
    if(rc||hash(output+8,n)!=a74_expected[A74_FULL][k])return 1;
    for(unsigned i=0;i<sizeof(output);++i)if((i<8||i>=8+n)&&output[i]!=0x5a)return 2;
    if(REG32(AI_BASE+0x204)!=0)return 3;
    return 0;
}
int main(void){
    uart_init(CLK_HZ,BAUD);prepare();uint32_t hi=hash(input,sizeof(input)),hw=hash(weights,sizeof(weights)),hp=hash(params,sizeof(params));
    for(unsigned k=0;k<SHAPES;++k){uint64_t a,b;if(run(k,1,&a)||run(k,2,&b))return 1;
        for(unsigned sample=0;sample<3;++sample){
            if(sample&1){if(run(k,2,&b)||run(k,1,&a))return 2;}else if(run(k,1,&a)||run(k,2,&b))return 3;
            uart_puts("A74_SAMPLE shape=");uart_putdec(k);uart_puts(" sample=");uart_putdec(sample);uart_puts(" ");field("control",a);uart_puts(" ");field("candidate",b);uart_puts("\n");
        }
    }
    if(hash(input,sizeof(input))!=hi||hash(weights,sizeof(weights))!=hw||hash(params,sizeof(params))!=hp)return 4;
    uart_puts("A74_DIAGNOSTIC_PASS full=");uart_putdec(A74_FULL);uart_puts(" samples=");uart_putdec(SHAPES*3);uart_puts(" readonly=PASS raw_mode=PASS\n");a74_result=1;return 0;
}
