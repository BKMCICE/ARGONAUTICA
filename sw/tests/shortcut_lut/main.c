#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
#define INT8_SHORTCUT_LUT_TYPES_ONLY
#include "../../common/int8_shortcut_lut.h"
#include "expected.h"
void a65_control(const YoloLayer *,const int8_t *,const int8_t *,int8_t *);
void a65_candidate(const YoloLayer *,const int8_t *,const int8_t *,int8_t *,Int8ShortcutLut *);
#ifndef A65_FULL
#define A65_FULL 0
#endif
#if A65_FULL
#define CAP 102400u
#else
#define CAP 257u
#endif
static int8_t input[CAP+16],source[CAP+16],output[CAP+16];
static struct { uint32_t before; Int8ShortcutLut lut; uint32_t after; } scratch;
volatile uint32_t a65_result;
void *memset(void *dest,int value,__SIZE_TYPE__ n) {unsigned char *p=dest;for(__SIZE_TYPE__ i=0;i<n;++i)p[i]=(unsigned char)value;return dest;}
static int8_t signed_byte(uint32_t x) {x&=255;return (int8_t)(x<128?(int32_t)x:(int32_t)x-256);}
static uint32_t hash(const int8_t *p,uint32_t n) {uint32_t h=2166136261u;for(uint32_t i=0;i<n;++i)h=(h^(uint8_t)p[i])*16777619u;return h;}
static void hex64(uint64_t v) {uart_puthex((uint32_t)(v>>32));uart_puthex((uint32_t)v);}
static uint64_t measure(unsigned candidate,const YoloLayer *l) {
    uint64_t start=rdcycle64();
    if(candidate)a65_candidate(l,input,source,output,&scratch.lut);
    else a65_control(l,input,source,output);
    return rdcycle64()-start;
}
static int valid(uint32_t n,uint32_t expected) {
    if(hash(output,n)!=expected || scratch.before!=0x51acb009 || scratch.after!=0x21d3a71f)return 0;
    for(uint32_t i=n;i<CAP+16;++i)if((uint8_t)output[i]!=0x5d)return 0;
    return 1;
}
int main(void) {
    uart_init(CLK_HZ,BAUD);uart_puts("A65_SHORTCUT_START full=");uart_putdec(A65_FULL);uart_putc('\n');
    scratch.before=0x51acb009;scratch.after=0x21d3a71f;
    for(unsigned k=0;k<18;++k) {
        unsigned index=a65_layers[k];YoloLayer layer=yolo_layers[index];uint32_t n=layer.oh*layer.ow*layer.oc;
#if !A65_FULL
        if(n>257)n=257;layer.oh=1;layer.ow=n;layer.oc=1;
#endif
        uint32_t expected=A65_FULL?a65_expected[k]:a65_expected_short[k];
        for(uint32_t i=0;i<n;++i) {input[i]=signed_byte((i*73+index*17)^(i>>8));source[i]=signed_byte(i*151+index*23+5);}
        uint32_t ihash=hash(input,n),shash=hash(source,n);
        for(unsigned warm=0;warm<2;++warm) {memset(output,0x5d,sizeof output);measure(warm,&layer);if(!valid(n,expected))goto fail;}
        for(unsigned sample=0;sample<3;++sample) {
            uint64_t control_cycles,candidate_cycles;
            for(unsigned order=0;order<2;++order) {
                unsigned candidate=(sample+order)&1;memset(output,0x5d,sizeof output);
                uint64_t cycles=measure(candidate,&layer);if(!valid(n,expected))goto fail;
                if(candidate)candidate_cycles=cycles;else control_cycles=cycles;
            }
            uart_puts("A65_SAMPLE layer=");uart_putdec(index);uart_puts(" count=");uart_putdec(n);uart_puts(" sample=");uart_putdec(sample);
            uart_puts(" control=0x");hex64(control_cycles);uart_puts(" candidate=0x");hex64(candidate_cycles);uart_putc('\n');
        }
        if(hash(input,n)!=ihash || hash(source,n)!=shash)goto fail;
    }
    a65_result=1;uart_puts("A65_SHORTCUT_PASS\n");return 0;
fail:
    a65_result=2;uart_puts("A65_SHORTCUT_FAIL\n");return 1;
}
