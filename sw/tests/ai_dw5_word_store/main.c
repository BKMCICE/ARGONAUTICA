#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
#include "expected.h"
int a88_control(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a88_placebo(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a88_candidate(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
volatile uint32_t a88_result,a88_phase;
#ifndef A88_FULL
#define A88_FULL 0
#endif
#if A88_FULL
#define CAP 48000
#define SHAPES 2
#else
#define CAP 8192
#define SHAPES 8
#endif
static int8_t input[CAP+16],output[CAP+32],weights[128*25+16];
static int32_t params[256];
void *memset(void *d,int v,__SIZE_TYPE__ n){unsigned char *p=d;for(__SIZE_TYPE__ i=0;i<n;++i)p[i]=(unsigned char)v;return d;}
static const uint32_t geometries[8][7]={
 {3,9,120,1,2,1,0},{5,17,3,1,2,1,0},{7,19,3,2,2,0,0},{1,1,2,1,2,1,0},
 {3,3,2,1,4,0,1},{8,10,4,1,0,1,0},{3,8,1,1,2,0,0},{2,7,2,3,2,1,0}};
static YoloLayer shape(unsigned k){
    YoloLayer l={0};l.kind=YOLO_CONV;l.size=5;
#if A88_FULL
    l.ih=l.iw=k?10:20;l.ic=l.oc=l.groups=k?96:120;l.stride=1;l.pad=2;l.leaky=1;
#else
    l.ih=geometries[k][0];l.iw=geometries[k][1];l.ic=l.oc=l.groups=geometries[k][2];l.stride=geometries[k][3];l.pad=geometries[k][4];l.leaky=geometries[k][5];
#endif
    l.oh=(l.ih+2*l.pad-5)/l.stride+1;l.ow=(l.iw+2*l.pad-5)/l.stride+1;
#if !A88_FULL
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
static int run(unsigned k,unsigned phase,unsigned align,uint64_t *elapsed){
    YoloLayer l=shape(k);uint32_t n=l.oc*l.oh*l.ow;
    for(unsigned i=0;i<sizeof(output);++i)output[i]=0x5a;
    a88_phase=phase;uint64_t start=rdcycle64();
    int rc=phase==1?a88_control(&l,input+8,output+8+align,weights+8,params):phase==2?a88_placebo(&l,input+8,output+8+align,weights+8,params):a88_candidate(&l,input+8,output+8+align,weights+8,params);
    *elapsed=rdcycle64()-start;a88_phase=0;
    if(rc||hash(output+8+align,n)!=a88_expected[A88_FULL][k])return 1;
    for(unsigned i=0;i<sizeof(output);++i)if((i<8+align||i>=8+align+n)&&output[i]!=0x5a)return 2;
    if(REG32(AI_BASE+0x204)!=0)return 3;
    return 0;
}
int main(void){
    uart_init(CLK_HZ,BAUD);prepare();uint32_t hi=hash(input,sizeof(input)),hw=hash(weights,sizeof(weights)),hp=hash(params,sizeof(params));
    uart_puts("A88_POST_ID=0x");uart_puthex(REG32(AI_BASE+0x2c));uart_puts("\n");
    if(REG32(AI_BASE+0x2c)!=0x41343831u)return 5;
    const unsigned orders[6][3]={{1,2,3},{1,3,2},{2,1,3},{2,3,1},{3,1,2},{3,2,1}};
    for(unsigned k=0;k<SHAPES;++k)for(unsigned align=0;align<4;++align){
        uint64_t elapsed[3];for(unsigned v=1;v<=3;++v)if(run(k,v,align,&elapsed[v-1]))return 1;
        for(unsigned sample=0;sample<6;++sample){
            for(unsigned j=0;j<3;++j){unsigned v=orders[sample][j];if(run(k,v,align,&elapsed[v-1]))return 2;}
            uart_puts("A88_SAMPLE shape=");uart_putdec(k);uart_puts(" align=");uart_putdec(align);uart_puts(" sample=");uart_putdec(sample);uart_puts(" ");
            field("control",elapsed[0]);uart_puts(" ");field("placebo",elapsed[1]);uart_puts(" ");field("candidate",elapsed[2]);uart_puts("\n");
        }
    }
    if(hash(input,sizeof(input))!=hi||hash(weights,sizeof(weights))!=hw||hash(params,sizeof(params))!=hp)return 4;
    uart_puts("A88_DIAGNOSTIC_PASS full=");uart_putdec(A88_FULL);uart_puts(" samples=");uart_putdec(SHAPES*4*6);uart_puts(" readonly=PASS raw_mode=PASS\n");a88_result=1;return 0;
}
