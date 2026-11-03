/* Diagnostic: true production operator in separate control/profile TUs.
 * Independent CHW/Q24 oracle on host; full target outputs match both each
 * other byte-for-byte and a frozen independently generated FNV reference. */
#include "diag.h"
#include "expected.h"
#ifndef YOLO_HOST_TEST
#include "../../common/ai_mac_block.h"
#endif
#ifdef YOLO_HOST_TEST
#include <stdio.h>
#include "../ai_1x1_block_layer/host_mmio.h"
uint32_t host_ai_calls;
#else
volatile uint32_t a19_result;
void *memset(void *d,int v,__SIZE_TYPE__ n){volatile unsigned char *p=d;for(__SIZE_TYPE__ i=0;i<n;++i)p[i]=(unsigned char)v;return d;}
#endif
#if A19_SHORT
#define IN_CAP 512
#define OUT_CAP 512
#define W_CAP 512
#else
#define IN_CAP 48000
#define OUT_CAP 153600
#define W_CAP 30600
#endif
static int8_t input[IN_CAP+16],weights[W_CAP+16],actual[OUT_CAP+16],prior[OUT_CAP+16];
static int32_t params[510];
static const uint32_t shapes[4][4]={{2,9,10,5},{3,7,17,9},{20,20,120,255},{40,40,16,96}};
static uint32_t hash(const void *buf,uint32_t n){const uint8_t *p=buf;uint32_t h=2166136261u;for(uint32_t i=0;i<n;++i)h=(h^p[i])*16777619u;return h;}
static YoloLayer shape(unsigned index){YoloLayer l={0};l.kind=YOLO_CONV;l.size=l.stride=l.groups=1;l.ih=l.oh=shapes[index][0];l.iw=l.ow=shapes[index][1];l.ic=shapes[index][2];l.oc=shapes[index][3];l.leaky=1;return l;}
static void prepare(unsigned seed){
 for(unsigned i=0;i<sizeof(input);++i)input[i]=(int8_t)(i*73u+seed*19u);
 for(unsigned i=0;i<sizeof(weights);++i)weights[i]=(int8_t)(i*59u+seed*31u);
 for(unsigned i=0;i<255;++i){params[2*i]=(i&1?-1:1)*(16384+(int32_t)i*29);params[2*i+1]=(int32_t)(i%17)-8;}
 for(unsigned i=0;i<sizeof(actual);++i)actual[i]=prior[i]=0x5a;
}
static int check(const YoloLayer *l,unsigned index,unsigned seed){
 uint32_t n=l->oc*l->oh*l->ow;
 for(uint32_t i=0;i<sizeof(actual);++i){
  if(actual[i]!=prior[i])return 1;
  if((i<8||i>=8+n)&&actual[i]!=0x5a)return 2;
 }
 if(hash(actual+8,n)!=a19_expected[seed-1][index])return 3;
 return 0;
}
#ifdef YOLO_HOST_TEST
static int32_t scale(int64_t dot,int32_t m){int64_t p=dot*m,n=((p<0?-p:p)+8388608)/16777216;return(int32_t)(p<0?-n:n);}
static int oracle(const YoloLayer *l){
 uint32_t plane=l->ih*l->iw;
 for(uint32_t oc=0;oc<l->oc;++oc)for(uint32_t px=0;px<plane;++px){int64_t dot=0;
  for(uint32_t c=0;c<l->ic;++c)dot+=(int32_t)input[8+c*plane+px]*weights[8+oc*l->ic+c];
  int32_t v=scale(dot,params[2*oc])+params[2*oc+1];if(v<0)v=scale(v,1677722);if(v>127)v=127;if(v< -127)v=-127;
  if(actual[8+oc*plane+px]!=v)return 1;
 }return 0;
}
#else
static void field(const char *name,uint64_t value){uart_puts(name);uart_puts("=0x");uart_puthex((uint32_t)(value>>32));uart_puthex((uint32_t)value);}
static void report(unsigned index,unsigned sample,uint64_t baseline,uint64_t profile,const A19Stats *s){
 uart_puts("A19_SAMPLE shape=");uart_putdec(index);uart_puts(" sample=");uart_putdec(sample);
 field(" baseline",baseline);field(" profile",profile);field(" cache",s->cache_cycles);field(" weight",s->weight_cycles);
 const char *names[6]={" setup"," pack"," write"," wait"," read"," q24"};
 for(unsigned i=0;i<6;++i)field(names[i],s->phase[i]);
 field(" task",s->task_cycles);field(" engine",s->engine_cycles);
 uart_puts(" tasks=");uart_putdec(s->tasks);uart_puts(" samples=");uart_putdec(s->samples);uart_puts(" batches=");uart_putdec(s->batches);
 uart_puts(" wwords=");uart_putdec(s->weight_words);uart_puts(" iwords=");uart_putdec(s->input_words);uart_puts(" rwords=");uart_putdec(s->result_words);
 uart_puts(" vectors=");uart_putdec(s->vectors);uart_puts(" dots=");uart_putdec(s->dots);uart_putc('\n');
}
#endif
int main(void){
 unsigned cases=0;
#ifdef YOLO_HOST_TEST
 for(unsigned seed=1;seed<=2;++seed)for(unsigned k=0;k<4;++k){YoloLayer l=shape(k);prepare(seed);a03_reset(0);
  uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
  if(a19_control(&l,input+8,actual+8,weights+8,params)||oracle(&l))return 10;
  for(unsigned i=0;i<sizeof(actual);++i)prior[i]=actual[i];
  if(check(&l,k,seed))return 11;
  if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 12;
  if(a03_starts!=((l.oc+3)/4)*l.oh*((l.ow+7)/8)||a03_weight_words!=l.oc*((l.ic+8)/9)*3)return 13;
  ++cases;
 }printf("A19_HOST_ORACLE_PASS cases=%u\n",cases);return 0;
#else
 uart_init(CLK_HZ,BAUD);if(AI_BLOCK_READ(AI_BLOCK_REG_ID)!=AI_BLOCK_ID)return 90;AI_BIAS=0;
 for(unsigned k=0;k<(A19_SHORT?2u:4u);++k){YoloLayer l=shape(k);prepare(1);
  uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));
  if(a19_control(&l,input+8,prior+8,weights+8,params)||a19_profile(&l,input+8,actual+8,weights+8,params)||check(&l,k,1))return 20;
  for(unsigned sample=0;sample<(A19_SHORT?1u:4u);++sample){uint64_t a,b,t;A19Stats stats;
   if(sample&1){t=rdcycle64();if(a19_profile(&l,input+8,actual+8,weights+8,params))return 21;b=rdcycle64()-t;
    t=rdcycle64();if(a19_control(&l,input+8,prior+8,weights+8,params))return 22;a=rdcycle64()-t;
   }else{t=rdcycle64();if(a19_control(&l,input+8,prior+8,weights+8,params))return 23;a=rdcycle64()-t;
    t=rdcycle64();if(a19_profile(&l,input+8,actual+8,weights+8,params))return 24;b=rdcycle64()-t;}
   if(check(&l,k,1))return 25;
   a19_stats(&stats);
   uint32_t tasks=((l.oc+3)/4)*l.oh*((l.ow+7)/8),samples=0,nn=0,iw=0,rw=0,dots=0;
   for(uint32_t oc=0;oc<l.oc;oc+=4)for(uint32_t y=0;y<l.oh;++y)for(uint32_t x=0;x<l.ow;x+=8){
    uint32_t out=l.oc-oc;if(out>4)out=4;uint32_t pixels=l.ow-x;if(pixels>8)pixels=8;
    if(!(nn&63)||(y+1==l.oh&&x+pixels==l.ow&&oc+out==l.oc)){++samples;iw+=((l.ic+8)/9)*pixels*3;rw+=out*pixels;dots+=((l.ic+8)/9)*pixels*out;}++nn;
   }
   if(stats.tasks!=tasks||stats.samples!=samples||stats.batches!=(l.oc+3)/4||stats.weight_words!=l.oc*((l.ic+8)/9)*3||stats.input_words!=iw||stats.result_words!=rw||stats.dots!=dots||stats.phase[1]!=0||!stats.cache_cycles||!stats.phase[2])return 26;
   report(k,sample,a,b,&stats);++cases;
  }
  if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 27;
 }
 uart_puts("A19_DIAGNOSTIC_PASS samples=");uart_putdec(cases);uart_putc('\n');a19_result=1;return 0;
#endif
}
