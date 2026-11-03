/* Three whole-operator variants, identical buffers and warmup/order schedule. */
#include "diag.h"
#include "expected.h"
#include "../../common/ai_mac_block.h"
volatile uint32_t a90_result;
void *memset(void*d,int v,__SIZE_TYPE__ n){volatile unsigned char*p=d;for(__SIZE_TYPE__ i=0;i<n;++i)p[i]=(unsigned char)v;return d;}
#define CAP 204800
static int8_t input[CAP+32] __attribute__((aligned(16))),out[CAP+32] __attribute__((aligned(16))),control[CAP+32],post_output[CAP+32],weights[64*9+16];
static int32_t params[128];
/* h,w,c,stride,pad,leaky,cropped_h,cropped_w,input_offset */
static const uint32_t shapes[8][9]={{80,80,32,1,1,1,0,0,0},{160,160,8,1,1,1,0,0,0},{40,40,48,1,1,1,0,0,0},{7,19,3,2,1,0,0,0,0},{5,9,1,1,2,0,3,4,0},{1,1,2,1,1,1,0,0,0},{80,80,32,1,1,1,0,0,1},{5,17,2,1,1,1,0,0,0}};
static YoloLayer shape(unsigned k){YoloLayer l={0};l.kind=YOLO_CONV;l.size=3;l.ih=shapes[k][0];l.iw=shapes[k][1];l.ic=l.oc=l.groups=shapes[k][2];l.stride=shapes[k][3];l.pad=shapes[k][4];l.leaky=shapes[k][5];l.oh=shapes[k][6]?shapes[k][6]:(l.ih+2*l.pad-3)/l.stride+1;l.ow=shapes[k][7]?shapes[k][7]:(l.iw+2*l.pad-3)/l.stride+1;return l;}
static uint32_t hash(const void*p,uint32_t n){const uint8_t*x=p;uint32_t h=2166136261u;for(uint32_t i=0;i<n;++i)h=(h^x[i])*16777619u;return h;}
static void prepare(void){for(unsigned i=0;i<sizeof(input);++i)input[i]=(int8_t)(i*73u+19u);for(unsigned i=0;i<sizeof(weights);++i)weights[i]=(int8_t)(i*59u+31u);for(unsigned i=0;i<64;++i){params[2*i]=(i&1?-1:1)*(16384+(int32_t)i*29);params[2*i+1]=(int32_t)(i%17)-8;}for(unsigned i=0;i<sizeof(out);++i)out[i]=control[i]=post_output[i]=0x5a;}
static int run(unsigned op,const YoloLayer*l,unsigned k){const int8_t*x=input+8+shapes[k][8];int rc=op==0?a90_control(l,x,control+8,weights+8,params):op==1?a90_post(l,x,post_output+8,weights+8,params):a90_raw(l,x,out+8,weights+8,params);return rc?rc:REG32(AI_BASE+0x204)!=0;}
static int check(const YoloLayer*l,unsigned k){uint32_t n=l->oc*l->oh*l->ow;for(unsigned i=0;i<sizeof(out);++i){if(out[i]!=control[i]||out[i]!=post_output[i])return 1;if((i<8||i>=8+n)&&out[i]!=0x5a)return 2;}return hash(out+8,n)!=a90_expected[k];}
static int guards(unsigned*n){YoloLayer l=shape(7),v;*n=0;prepare();
#define BAD(a,b,c,d,e) do{if(a90_control(a,b,c,d,e)!=AI_BLOCK_BAD_SHAPE||a90_post(a,b,c,d,e)!=AI_BLOCK_BAD_SHAPE||a90_raw(a,b,c,d,e)!=AI_BLOCK_BAD_SHAPE)return 1;++*n;}while(0)
 BAD(0,input+8,out+8,weights+8,params);BAD(&l,0,out+8,weights+8,params);BAD(&l,input+8,0,weights+8,params);BAD(&l,input+8,out+8,0,params);BAD(&l,input+8,out+8,weights+8,0);
#define FIELD(f,x) do{v=l;v.f=x;BAD(&v,input+8,out+8,weights+8,params);}while(0)
 FIELD(kind,2);FIELD(size,1);FIELD(groups,1);FIELD(ic,0);FIELD(oc,1);FIELD(stride,0);FIELD(stride,3);FIELD(pad,3);FIELD(ih,0);FIELD(iw,0);FIELD(oh,0);FIELD(ow,0);FIELD(oh,100);FIELD(ow,100);FIELD(ih,INT32_MAX);FIELD(iw,UINT32_MAX);v=l;v.ic=v.oc=v.groups=UINT32_MAX;BAD(&v,input+8,out+8,weights+8,params);
 BAD(&l,input+8,input+8,weights+8,params);BAD(&l,input+8,weights+8,weights+8,params);BAD(&l,input+8,(int8_t*)params,weights+8,params);
 const void*p=(const void*)(UINTPTR_MAX-4);BAD(&l,p,out+8,weights+8,params);BAD(&l,input+8,(int8_t*)p,weights+8,params);BAD(&l,input+8,out+8,p,params);BAD(&l,input+8,out+8,weights+8,p);
#undef BAD
#undef FIELD
 return 0;}
static void field(const char*n,uint64_t x){uart_puts(n);uart_puts("=0x");uart_puthex((uint32_t)(x>>32));uart_puthex((uint32_t)x);}
int main(void){uart_init(CLK_HZ,BAUD);AI_BIAS=0;uart_puts("A90_POST_ID=0x");uart_puthex(REG32(AI_BASE+0x2c));uart_putc('\n');if(REG32(AI_BASE+0x2c)!=0x41343831u)return 5;unsigned g=0,count=0;if(guards(&g))return 10;uart_puts("A90_GUARDS_PASS count=");uart_putdec(g);uart_putc('\n');
 static const uint8_t order[6][3]={{0,1,2},{1,2,0},{2,0,1},{2,1,0},{1,0,2},{0,2,1}};
 for(unsigned k=0;k<8;++k){YoloLayer l=shape(k);prepare();uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights)),ph=hash(params,sizeof(params));for(unsigned op=0;op<3;++op)if(run(op,&l,k))return 20;if(check(&l,k))return 21;
  for(unsigned sample=0;sample<6;++sample){uint64_t t[3];for(unsigned i=0;i<3;++i){unsigned op=order[sample][i];uint64_t start=rdcycle64();if(run(op,&l,k))return 22;t[op]=rdcycle64()-start;}if(check(&l,k))return 23;uart_puts("A90_SAMPLE shape=");uart_putdec(k);uart_puts(" sample=");uart_putdec(sample);field(" control",t[0]);field(" post8",t[1]);field(" raw",t[2]);uart_putc('\n');++count;}
  /* Separate untimed repeats: these counters describe the final row task only. */
  if(run(1,&l,k)||check(&l,k))return 25;
  uint32_t pm=REG32(AI_BASE+0x124),pi=REG32(AI_BASE+0x128),pq=REG32(AI_BASE+0x228),pn=REG32(AI_BASE+0x22c);
  if(run(2,&l,k)||check(&l,k))return 26;
  uint32_t rm=REG32(AI_BASE+0x124),ri=REG32(AI_BASE+0x128),tail=(l.ow-1u)%8u+1u;
  if(pi!=tail||ri!=tail||pn!=tail||pm!=rm||!pq)return 27;
  uart_puts("A90_LAST_TASK shape=");uart_putdec(k);field(" pixels",tail);field(" post_mac",pm);field(" post_extra",pq);field(" post_items",pn);field(" raw_mac",rm);field(" raw_dots",ri);uart_putc('\n');
  if(hash(input,sizeof(input))!=ih||hash(weights,sizeof(weights))!=wh||hash(params,sizeof(params))!=ph)return 24;
 }
 uart_puts("A90_DIAGNOSTIC_PASS samples=");uart_putdec(count);uart_putc('\n');a90_result=1;return 0;}
