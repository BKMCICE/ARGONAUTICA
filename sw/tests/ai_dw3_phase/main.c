/* Whole production control vs separately instrumented rolling operator.
 * Sampling changes layout and execution; these are diagnostic windows only. */
#include "diag.h"
#include "expected.h"
#ifdef YOLO_HOST_TEST
#include <stdio.h>
uint32_t host_ai_calls;
#else
volatile uint32_t a29_result;
void *memset(void *d,int v,__SIZE_TYPE__ n){unsigned char *p=d;for(__SIZE_TYPE__ i=0;i<n;++i)p[i]=(unsigned char)v;return d;}
#endif
#include "../../common/ai_mac_block.h"
#if A29_SHORT
#define CAP 1024
#else
#define CAP 204800
#endif
static int8_t input[CAP+16],actual[CAP+16],prior[CAP+16],weights[64*9+16];
static int32_t params[128];
/* ih,iw,c,stride,pad,leaky,cropped_oh,cropped_ow. k2/k3/k7 are real geometries. */
static const uint32_t shapes[8][8]={
 {5,17,2,1,1,1,0,0},{7,19,3,2,1,0,0,0},
 {80,80,32,1,1,1,0,0},{160,160,8,1,1,1,0,0},
 {80,80,32,2,1,0,0,0},{1,1,2,1,1,1,0,0},
 {5,9,1,1,2,0,3,4},{40,40,48,1,1,1,0,0}
};
static YoloLayer shape(unsigned k)
{
 YoloLayer l={0};l.kind=YOLO_CONV;l.size=3;l.ih=shapes[k][0];l.iw=shapes[k][1];
 l.ic=l.oc=l.groups=shapes[k][2];l.stride=shapes[k][3];l.pad=shapes[k][4];l.leaky=shapes[k][5];
 l.oh=shapes[k][6]?shapes[k][6]:(l.ih+2*l.pad-3)/l.stride+1;
 l.ow=shapes[k][7]?shapes[k][7]:(l.iw+2*l.pad-3)/l.stride+1;return l;
}
static uint32_t hash(const void *p,uint32_t n)
{
 const uint8_t *x=p;uint32_t h=2166136261u;for(uint32_t i=0;i<n;++i)h=(h^x[i])*16777619u;return h;
}
static void prepare(unsigned seed)
{
 for(unsigned i=0;i<sizeof(input);++i)input[i]=seed==2?-128:(int8_t)(i*73u+seed*19u);
 for(unsigned i=0;i<sizeof(weights);++i)weights[i]=seed==2?-128:(int8_t)(i*59u+seed*31u);
 for(unsigned i=0;i<64;++i){params[2*i]=(i&1?-1:1)*(seed==2?256:16384+(int32_t)i*29);params[2*i+1]=(int32_t)(i%17)-8;}
 for(unsigned i=0;i<sizeof(actual);++i)actual[i]=prior[i]=0x5a;
}
static int check(const YoloLayer *l,unsigned k,unsigned seed)
{
 uint32_t n=l->oc*l->oh*l->ow;
 for(uint32_t i=0;i<sizeof(actual);++i){if(actual[i]!=prior[i])return 1;
  if((i<8||i>=8+n)&&actual[i]!=0x5a)return 2;}
 if(k<8&&hash(actual+8,n)!=a29_expected[seed-1][k])return 3;
 return 0;
}
/* Independent geometry classification, not the production first/last formula. */
static int counts(const YoloLayer *l,const A29Stats *s)
{
 uint32_t inner=0,border=0,seeds=0,samples=0,updates=0;
 for(uint32_t c=0;c<l->oc;++c)for(uint32_t y=0;y<l->oh;++y){unsigned row=0;
  for(uint32_t x=0;x<l->ow;++x){
   int64_t yy=(int64_t)y*l->stride-l->pad,xx=(int64_t)x*l->stride-l->pad;
   if(yy>=0&&yy+2<l->ih&&xx>=0&&xx+2<l->iw){
    if(!row++)++seeds;
    if(!(inner&63)){++samples;if(x+1<l->ow&&xx+l->stride+2<l->iw)++updates;}
    ++inner;
   }else ++border;
  }
 }
 return s->interior!=inner||s->boundary!=border||s->seeds!=seeds||
        s->samples!=samples||s->updates!=updates||s->weights!=l->oc;
}
#ifdef YOLO_HOST_TEST
static int32_t scale(int64_t dot,int32_t m)
{
 int64_t p=dot*m,n=((p<0?-p:p)+8388608)/16777216;return(int32_t)(p<0?-n:n);
}
static int oracle(const YoloLayer *l)
{
 for(uint32_t c=0;c<l->oc;++c)for(uint32_t y=0;y<l->oh;++y)for(uint32_t x=0;x<l->ow;++x){
  int64_t dot=0;
  for(uint32_t ky=0;ky<3;++ky)for(uint32_t kx=0;kx<3;++kx){
   int64_t yy=(int64_t)y*l->stride+ky-l->pad,xx=(int64_t)x*l->stride+kx-l->pad;
   if(yy>=0&&yy<l->ih&&xx>=0&&xx<l->iw)
    dot+=(int32_t)input[8+(c*l->ih+(uint32_t)yy)*l->iw+(uint32_t)xx]*weights[8+c*9+ky*3+kx];
  }
  int32_t v=scale(dot,params[2*c])+params[2*c+1];if(l->leaky&&v<0)v=scale(v,1677722);
  if(v>127)v=127;if(v< -127)v=-127;
  if(actual[8+(c*l->oh+y)*l->ow+x]!=v)return 1;
 }return 0;
}
static int host_case(YoloLayer l,unsigned k,unsigned seed)
{
 prepare(seed);host_ai_calls=0;
 uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
 if(a29_control(&l,input+8,prior+8,weights+8,params)||a29_profile(&l,input+8,actual+8,weights+8,params))return 1;
 A29Stats s;a29_stats(&s);
 if(oracle(&l)||check(&l,k,seed)||counts(&l,&s)||host_ai_calls!=2*l.oc*l.oh*l.ow)return 2;
 if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 3;
 return 0;
}
#else
static void field(const char *name,uint64_t v)
{
 uart_puts(name);uart_puts("=0x");uart_puthex((uint32_t)(v>>32));uart_puthex((uint32_t)v);
}
static void report(unsigned k,unsigned sample,uint64_t a,uint64_t b,const A29Stats *s)
{
 uart_puts("A29_SAMPLE shape=");uart_putdec(k);uart_puts(" sample=");uart_putdec(sample);
 field(" control",a);field(" profile",b);field(" weight",s->weight);field(" seed",s->seed);field(" border",s->border);
 const char *names[]={" pack"," write"," wait"," read"," q24"," advance"};
 for(unsigned i=0;i<A29_PHASES;++i)field(names[i],s->phase[i]);
 uart_puts(" interior=");uart_putdec(s->interior);uart_puts(" boundary=");uart_putdec(s->boundary);
 uart_puts(" samples=");uart_putdec(s->samples);uart_puts(" updates=");uart_putdec(s->updates);
 uart_puts(" seeds=");uart_putdec(s->seeds);uart_puts(" weights=");uart_putdec(s->weights);
 uart_puts(" polls=");uart_putdec(s->polls);uart_putc('\n');
}
#endif
static int guards(unsigned *n)
{
 YoloLayer l=shape(0),v;prepare(1);*n=0;
#ifdef YOLO_HOST_TEST
 host_ai_calls=0;
#endif
 uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
#define BAD(a,b,c,d,e) do{if(a29_control(a,b,c,d,e)!=AI_BLOCK_BAD_SHAPE||a29_profile(a,b,c,d,e)!=AI_BLOCK_BAD_SHAPE)return 1;++*n;}while(0)
 BAD(0,input+8,actual+8,weights+8,params);BAD(&l,0,actual+8,weights+8,params);
 BAD(&l,input+8,0,weights+8,params);BAD(&l,input+8,actual+8,0,params);BAD(&l,input+8,actual+8,weights+8,0);
#define FIELD(name,value) do{v=l;v.name=value;BAD(&v,input+8,actual+8,weights+8,params);}while(0)
 FIELD(kind,2);FIELD(size,1);FIELD(groups,1);FIELD(ic,0);FIELD(oc,1);FIELD(stride,0);FIELD(stride,3);
 FIELD(pad,3);FIELD(ih,0);FIELD(iw,0);FIELD(oh,0);FIELD(ow,0);FIELD(oh,100);FIELD(ow,100);
 FIELD(ih,INT32_MAX);FIELD(iw,UINT32_MAX);v=l;v.ic=v.oc=v.groups=UINT32_MAX;BAD(&v,input+8,actual+8,weights+8,params);
 BAD(&l,input+8,input+8,weights+8,params);BAD(&l,input+8,weights+8,weights+8,params);BAD(&l,input+8,(int8_t *)params,weights+8,params);
 const void *p=(const void *)(UINTPTR_MAX-4);
 BAD(&l,p,actual+8,weights+8,params);BAD(&l,input+8,(int8_t *)p,weights+8,params);
 BAD(&l,input+8,actual+8,p,params);BAD(&l,input+8,actual+8,weights+8,p);
#undef FIELD
#undef BAD
 if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 2;
#ifdef YOLO_HOST_TEST
 if(host_ai_calls)return 3;
#endif
 return 0;
}
int main(void)
{
 unsigned n=0,cases=0;
#ifndef YOLO_HOST_TEST
 uart_init(CLK_HZ,BAUD);AI_BIAS=0;
#endif
 if(guards(&n))return 10;
#ifdef YOLO_HOST_TEST
 for(unsigned seed=1;seed<=2;++seed)for(unsigned k=0;k<8;++k){if(host_case(shape(k),k,seed))return 11;++cases;}
 for(unsigned k=0;k<144;++k){YoloLayer l=shape(0);l.ih=1+k%5;l.iw=1+(k*7)%19;
  l.pad=1+(k%2);l.stride=1+(k/2)%2;l.ic=l.oc=l.groups=1+k%3;l.leaky=k%2;
  l.oh=(l.ih+2*l.pad-3)/l.stride+1;l.ow=(l.iw+2*l.pad-3)/l.stride+1;
  if(k%3==0&&l.oh>1)--l.oh;if(k%4==0&&l.ow>1)--l.ow;
  if(host_case(l,8,1+k%2))return 12;++cases;
 }
 printf("A29_HOST_CONTROL_PROFILE_ORACLE_PASS cases=%u guards=%u counts=PASS\n",cases,n);return 0;
#else
 uart_puts("A29_GUARDS_PASS count=");uart_putdec(n);uart_putc('\n');
 uint64_t overhead=a29_clock_overhead();uart_puts("A29_CLOCK pairs=1024");field(" sum",overhead);uart_putc('\n');
 for(unsigned k=0;k<(A29_SHORT?2u:8u);++k){YoloLayer l=shape(k);prepare(1);
  uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
  if(a29_control(&l,input+8,prior+8,weights+8,params)||a29_profile(&l,input+8,actual+8,weights+8,params)||check(&l,k,1))return 20;
  for(unsigned sample=0;sample<(A29_SHORT?1u:4u);++sample){uint64_t a,b,t;A29Stats s;
   if(sample&1){t=rdcycle64();if(a29_profile(&l,input+8,actual+8,weights+8,params))return 21;b=rdcycle64()-t;
    t=rdcycle64();if(a29_control(&l,input+8,prior+8,weights+8,params))return 22;a=rdcycle64()-t;
   }else{t=rdcycle64();if(a29_control(&l,input+8,prior+8,weights+8,params))return 23;a=rdcycle64()-t;
    t=rdcycle64();if(a29_profile(&l,input+8,actual+8,weights+8,params))return 24;b=rdcycle64()-t;}
   a29_stats(&s);if(check(&l,k,1)||counts(&l,&s))return 25;
   report(k,sample,a,b,&s);++cases;
  }
  if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 26;
 }
 uart_puts("A29_DIAGNOSTIC_PASS samples=");uart_putdec(cases);uart_putc('\n');a29_result=1;return 0;
#endif
}
