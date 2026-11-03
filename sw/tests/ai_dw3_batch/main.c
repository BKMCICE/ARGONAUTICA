#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
#include "expected.h"
int a53_control(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a53_candidate(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
volatile uint32_t a53_result,a53_phase;
#ifndef A53_FULL
#define A53_FULL 0
#endif
#if A53_FULL
#define CAP 204800
#define SHAPES 2
#else
#define CAP 8192
#define SHAPES 8
#endif
static int8_t input[CAP+16],output[CAP+16],weights[64*9+16];
static int32_t params[128];
void *memset(void *d,int v,__SIZE_TYPE__ n){unsigned char *p=d;for(__SIZE_TYPE__ i=0;i<n;++i)p[i]=(unsigned char)v;return d;}
static const uint32_t geometries[8][7]={
 {5,17,2,1,1,1,0},{7,19,3,2,1,0,0},{8,20,4,1,1,1,0},
 {3,3,1,1,0,1,0},{1,1,2,1,1,1,0},{5,9,1,1,2,0,1},
 {10,18,8,1,1,1,0},{9,19,32,2,1,1,0}};
static YoloLayer shape(unsigned k){
    YoloLayer l={0};l.kind=YOLO_CONV;l.size=3;
#if A53_FULL
    l.ih=l.iw=k?160:80;l.ic=l.oc=l.groups=k?8:32;l.stride=1;l.pad=1;l.leaky=1;
#else
    l.ih=geometries[k][0];l.iw=geometries[k][1];l.ic=l.oc=l.groups=geometries[k][2];
    l.stride=geometries[k][3];l.pad=geometries[k][4];l.leaky=geometries[k][5];
#endif
    l.oh=(l.ih+2*l.pad-3)/l.stride+1;l.ow=(l.iw+2*l.pad-3)/l.stride+1;
#if !A53_FULL
    if(geometries[k][6]){--l.oh;--l.ow;}
#endif
    return l;
}
static uint32_t hash(const void *p,uint32_t n){
    const uint8_t *x=p;uint32_t h=2166136261u;for(uint32_t i=0;i<n;++i)h=(h^x[i])*16777619u;return h;
}
static void prepare(void){
    for(unsigned i=0;i<sizeof(input);++i)input[i]=(int8_t)(i*73u+19u);
    for(unsigned i=0;i<sizeof(weights);++i)weights[i]=(int8_t)(i*59u+31u);
    for(unsigned i=0;i<64;++i){params[i*2]=(i&1?-1:1)*(16384+(int32_t)i*29);params[i*2+1]=(int32_t)(i%17)-8;}
}
static void field(const char *name,uint64_t n){uart_puts(name);uart_puts("=0x");uart_puthex((uint32_t)(n>>32));uart_puthex((uint32_t)n);}
static int run(unsigned k,unsigned phase,uint64_t *elapsed){
    YoloLayer l=shape(k);uint32_t n=l.oc*l.oh*l.ow;
    for(unsigned i=0;i<sizeof(output);++i)output[i]=0x5a;
    a53_phase=phase;uint64_t start=rdcycle64();
    int rc=phase==1?a53_control(&l,input+8,output+8,weights+8,params):a53_candidate(&l,input+8,output+8,weights+8,params);
    *elapsed=rdcycle64()-start;a53_phase=0;
    if(rc||hash(output+8,n)!=a53_expected[A53_FULL][k])return 1;
    for(unsigned i=0;i<sizeof(output);++i)if((i<8||i>=8+n)&&output[i]!=0x5a)return 2;
    return 0;
}
int main(void){
    uart_init(CLK_HZ,BAUD);prepare();
    uint32_t hi=hash(input,sizeof(input)),hw=hash(weights,sizeof(weights)),hp=hash(params,sizeof(params));
    for(unsigned k=0;k<SHAPES;++k){uint64_t a,b;
        if(run(k,1,&a)||run(k,2,&b))return 1;
        for(unsigned sample=0;sample<3;++sample){
            if(sample&1){if(run(k,2,&b)||run(k,1,&a))return 2;}
            else if(run(k,1,&a)||run(k,2,&b))return 3;
            uart_puts("A53_SAMPLE shape=");uart_putdec(k);uart_puts(" sample=");uart_putdec(sample);
            uart_puts(" ");field("control",a);uart_puts(" ");field("candidate",b);uart_puts("\n");
        }
    }
    if(hash(input,sizeof(input))!=hi||hash(weights,sizeof(weights))!=hw||hash(params,sizeof(params))!=hp)return 4;
    uart_puts("A53_DIAGNOSTIC_PASS full=");uart_putdec(A53_FULL);uart_puts(" samples=");uart_putdec(SHAPES*3);uart_puts(" readonly=PASS\n");
    a53_result=1;return 0;
}
