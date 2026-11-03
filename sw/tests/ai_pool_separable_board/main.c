#include "diag.h"
#include "expected.h"
#include <limits.h>
volatile uint32_t a96_result;
static int8_t input[4832] __attribute__((aligned(32)));
static int8_t output[4832] __attribute__((aligned(32)));
static int8_t scratch[132] __attribute__((aligned(32)));
void *memset(void*d,int v,__SIZE_TYPE__ n){volatile unsigned char*p=d;for(__SIZE_TYPE__ i=0;i<n;++i)p[i]=(unsigned char)v;return d;}
void *memcpy(void*d,const void*s,__SIZE_TYPE__ n){volatile unsigned char*p=d;const volatile unsigned char*q=s;for(__SIZE_TYPE__ i=0;i<n;++i)p[i]=q[i];return d;}
static int8_t value(unsigned i,unsigned p){
    if(p==0)return (int8_t)(i*73u+19u);
    if(p==1)return (int8_t)(-1-(int32_t)((i*37u+11u)&127u));
    if(p==2)return -128;
    return (int8_t)((int32_t)(i%255u)-127);
}
static unsigned offset(unsigned shape){return 8u+shape%4u;}
static void prepare(unsigned shape){
    memset(input,0x51,sizeof(input));memset(output,0x5a,sizeof(output));memset(scratch,0x33,sizeof(scratch));
    unsigned off=offset(shape);for(unsigned i=0;i<4800;++i)input[off+i]=value(i,shape%4);
}
static int check(unsigned shape,unsigned candidate){
    unsigned off=offset(shape);uint32_t h=2166136261u;
    for(unsigned i=0;i<sizeof(input);++i){int8_t expect=i>=off&&i<off+4800?value(i-off,shape%4):(int8_t)0x51;if(input[i]!=expect)return 1;}
    for(unsigned i=0;i<sizeof(output);++i){int8_t expect=i>=off&&i<off+4800?expected_output[shape][i-off]:(int8_t)0x5a;if(output[i]!=expect)return 2;}
    for(unsigned i=0;i<4800;++i)h=(h^(uint8_t)output[off+i])*16777619u;
    if(h!=expected_fnv[shape])return 3;
    for(unsigned i=0;i<sizeof(scratch);++i)if((!candidate||i<off||i>=off+100)&&scratch[i]!=(int8_t)0x33)return 4;
    return 0;
}
static int run(unsigned op,const YoloLayer*l,unsigned shape,uint64_t *cycles){
    prepare(shape);unsigned off=offset(shape);int result;uint64_t start=rdcycle64();
    if(op==0)result=a96_control(l,input+off,output+off);
    else if(op==1)result=a96_placebo(l,input+off,output+off);
    else result=a96_candidate(l,input+off,output+off,scratch+off,100);
    *cycles=rdcycle64()-start;
    return result?5:check(shape,op==2);
}
static unsigned guards(void){
    for(unsigned k=0;k<18;++k){
        YoloLayer l=yolo_layers[109];const YoloLayer *lp=&l;const int8_t *ip=input;int8_t *op=output,*sp=scratch;unsigned n=100;
        switch(k){case 0:lp=0;break;case 1:ip=0;break;case 2:op=0;break;case 3:sp=0;break;case 4:n=99;break;case 5:l.kind=1;break;case 6:l.ih=9;break;case 7:l.iw=9;break;case 8:l.ic=47;break;case 9:l.oh=9;break;case 10:l.ow=9;break;case 11:l.oc=47;break;case 12:l.stride=2;break;case 13:l.size=1;break;case 14:l.size=7;break;case 15:l.pad=0;break;case 16:l.prev_q24=16777216;break;case 17:l.size=UINT32_MAX;break;}
        prepare(0);if(a96_candidate(lp,ip,op,sp,n)!=-2)return 1;
        for(unsigned i=0;i<sizeof(output);++i)if(output[i]!=(int8_t)0x5a)return 2;
        for(unsigned i=0;i<sizeof(scratch);++i)if(scratch[i]!=(int8_t)0x33)return 3;
        for(unsigned i=0;i<sizeof(input);++i)if(input[i]!=(i>=8&&i<4808?value(i-8,0):(int8_t)0x51))return 4;
    }
    return 0;
}
static void field(const char *name,uint64_t v){uart_puts(name);uart_puts("=0x");uart_puthex((uint32_t)(v>>32));uart_puthex((uint32_t)v);}
int main(void){
    uart_init(CLK_HZ,BAUD);if(guards())return 10;uart_puts("A96_GUARDS_PASS count=18\n");
    static const uint8_t order[6][3]={{0,1,2},{1,2,0},{2,0,1},{2,1,0},{1,0,2},{0,2,1}};
    static const unsigned index[3]={109,111,113};unsigned samples=0;
    for(unsigned shape=0;shape<12;++shape){
        const YoloLayer *l=&yolo_layers[index[shape/4]];uint64_t discarded;
        for(unsigned op=0;op<3;++op)if(run(op,l,shape,&discarded))return 20;
        for(unsigned sample=0;sample<6;++sample){
            uint64_t t[3];for(unsigned i=0;i<3;++i){unsigned op=order[sample][i];if(run(op,l,shape,&t[op]))return 21;}
            uart_puts("A96_SAMPLE shape=");uart_putdec(shape);uart_puts(" sample=");uart_putdec(sample);
            field(" control",t[0]);field(" placebo",t[1]);field(" candidate",t[2]);uart_putc('\n');++samples;
        }
    }
    uart_puts("A96_DIAGNOSTIC_PASS samples=");uart_putdec(samples);uart_putc('\n');a96_result=1;return 0;
}
