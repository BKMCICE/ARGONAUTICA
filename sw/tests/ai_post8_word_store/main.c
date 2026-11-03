#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
#include "geometry.h"
#include "expected.h"
int a79_control(const YoloLayer*,const int8_t*,int8_t*,const int8_t*,const int32_t*);
int a79_placebo(const YoloLayer*,const int8_t*,int8_t*,const int8_t*,const int32_t*);
int a79_candidate(const YoloLayer*,const int8_t*,int8_t*,const int8_t*,const int32_t*);
volatile uint32_t a79_result,a79_phase;
#ifndef A79_FULL
#define A79_FULL 0
#endif
#if A79_FULL
#define IN_CAP 204800
#define OUT_CAP 614400
#define W_CAP 57120
#define SAMPLES 6
#else
#define IN_CAP 4096
#define OUT_CAP 8192
#define W_CAP 8192
#define SAMPLES 3
#endif
static int8_t input[IN_CAP+16] __attribute__((aligned(32)));
static int8_t output[OUT_CAP+32] __attribute__((aligned(32)));
static int8_t weights[W_CAP+16] __attribute__((aligned(32)));
static int32_t params[510];
void *memset(void *d,int v,__SIZE_TYPE__ n){volatile unsigned char *p=d;for(__SIZE_TYPE__ i=0;i<n;++i)p[i]=(unsigned char)v;return d;}
static uint32_t hash(const void *p,uint32_t n){const uint8_t *x=p;uint32_t h=2166136261u;for(uint32_t i=0;i<n;++i)h=(h^x[i])*16777619u;return h;}
static YoloLayer shape(unsigned k){const uint32_t *v=a79_geometries[A79_FULL][k];YoloLayer l={0};l.kind=YOLO_CONV;l.size=1;l.ih=v[0];l.iw=v[1];l.ic=v[2]*v[4];l.oc=v[3]*v[4];l.groups=v[4];l.stride=v[5];l.leaky=1;l.oh=(l.ih-1)/l.stride+1;l.ow=(l.iw-1)/l.stride+1;return l;}
static void prepare(void){for(unsigned i=0;i<sizeof(input);++i)input[i]=(int8_t)(i*73u+19u);for(unsigned i=0;i<sizeof(weights);++i)weights[i]=(int8_t)(i*59u+31u);for(unsigned c=0;c<255;++c){params[2*c]=(c&1?-1:1)*(16384+(int32_t)c*29);params[2*c+1]=(int32_t)(c%17)-8;}}
static void field(const char *name,uint64_t n){uart_puts(name);uart_puts("=0x");uart_puthex((uint32_t)(n>>32));uart_puthex((uint32_t)n);}
static int run(unsigned k,unsigned op,uint64_t *elapsed){
 YoloLayer l=shape(k);unsigned n=l.oc*l.oh*l.ow,off=8+a79_geometries[A79_FULL][k][6];
 for(unsigned i=0;i<sizeof(output);++i)output[i]=0x5a;
 a79_phase=op+1;uint64_t start=rdcycle64();int rc;
 if(op==0)rc=a79_control(&l,input+8,output+off,weights+8,params);
 else if(op==1)rc=a79_placebo(&l,input+8,output+off,weights+8,params);
 else rc=a79_candidate(&l,input+8,output+off,weights+8,params);
 *elapsed=rdcycle64()-start;a79_phase=0;
 if(rc||hash(output+off,n)!=a79_expected[A79_FULL][k])return 1;
 for(unsigned i=0;i<sizeof(output);++i)if((i<off||i>=off+n)&&output[i]!=0x5a)return 2;
 if(REG32(AI_BASE+0x204)!=0)return 3;return 0;
}
int main(void){
 static const uint8_t orders[6][3]={{0,1,2},{1,2,0},{2,0,1},{0,2,1},{2,1,0},{1,0,2}};
 uart_init(CLK_HZ,BAUD);prepare();uint32_t hi=hash(input,sizeof(input)),hw=hash(weights,sizeof(weights)),hp=hash(params,sizeof(params));
 uart_puts("A79_POST_ID=0x");uart_puthex(REG32(AI_BASE+0x2c));uart_putc('\n');if(REG32(AI_BASE+0x2c)!=0x41343831u)return 5;
 for(unsigned k=0;k<8;++k){uint64_t t[3];for(unsigned op=0;op<3;++op)if(run(k,op,t+op))return 1;
  for(unsigned sample=0;sample<SAMPLES;++sample){for(unsigned i=0;i<3;++i){unsigned op=orders[sample][i];if(run(k,op,t+op))return 2;}
   uart_puts("A79_SAMPLE shape=");uart_putdec(k);uart_puts(" sample=");uart_putdec(sample);uart_puts(" ");field("control",t[0]);uart_puts(" ");field("placebo",t[1]);uart_puts(" ");field("candidate",t[2]);uart_putc('\n');
  }
 }
 if(hash(input,sizeof(input))!=hi||hash(weights,sizeof(weights))!=hw||hash(params,sizeof(params))!=hp)return 4;
 uart_puts("A79_DIAGNOSTIC_PASS full=");uart_putdec(A79_FULL);uart_puts(" samples=");uart_putdec(8*SAMPLES);uart_puts(" readonly=PASS raw_mode=PASS\n");a79_result=1;return 0;
}
