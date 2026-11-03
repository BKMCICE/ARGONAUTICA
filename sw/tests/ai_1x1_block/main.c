/* Same driver in host protocol model and a real-CPU SoC test; scalar oracle
 * reads original CHW bytes directly and never uses packed words or MMIO math. */
#include <stdint.h>
#ifdef BLOCK_HOST_TEST
#include <stdio.h>
#include <stdlib.h>
static uint32_t model_read(uint32_t off);
static void model_write(uint32_t off,uint32_t value);
#define AI_BLOCK_READ(off) model_read(off)
#define AI_BLOCK_WRITE(off,v) model_write(off,v)
#endif
#include "../../common/ai_mac_block.h"
#ifndef BLOCK_HOST_TEST
volatile uint32_t block_test_result;
#endif
static int8_t input[224*32+16],weights[4*227+16];
static int32_t output[34];
#ifndef BLOCK_HOST_TEST
static uint32_t packed_w[4*25*3],packed_p[25*8*3];
#endif
#ifdef BLOCK_HOST_TEST
static uint32_t mw[300],mp[600],mr[32],wi,pi,ri,ms,status,cycles,mdots,transactions;
static int mode;
static int32_t byte_at(uint32_t word,uint32_t lane) {return (int8_t)(word>>(lane*8));}
static uint32_t model_read(uint32_t off) {
    ++transactions;
    if(off==AI_BLOCK_REG_ID) return mode==1 ? 0:AI_BLOCK_ID;
    if(off==AI_BLOCK_CTRL) return mode==2 ? 0:mode==3 ? 6:mode==4 ? 1:status;
    if(off==AI_BLOCK_CYCLES) return cycles;
    if(off==AI_BLOCK_RDATA) {if(ri>=32) abort();return mr[ri++];}
    abort();
}
static void model_write(uint32_t off,uint32_t v) {
    ++transactions;
    switch(off) {
    case AI_BLOCK_WADDR:wi=0;return;case AI_BLOCK_PADDR:pi=0;return;case AI_BLOCK_RADDR:ri=v;return;
    case AI_BLOCK_WDATA:if(wi>=300) abort();mw[wi++]=v;return;
    case AI_BLOCK_PDATA:if(pi>=600) abort();mp[pi++]=v;return;
    case AI_BLOCK_SHAPE:ms=v;return;
    case AI_BLOCK_CTRL:
        if(v==4) {status=0;return;}
        if(v==1) {
            uint32_t n=ms&15,o=(ms>>4)&15,b=(ms>>8)&63,last=(ms>>16)&15;
            if(wi!=o*b*3 || pi!=b*n*3) abort();
            for(uint32_t oc=0;oc<o;++oc) for(uint32_t p=0;p<n;++p) {
                int32_t s=0;
                for(uint32_t k=0;k<b;++k) for(uint32_t l=0;l<(k==b-1?last:9);++l)
                    s+=byte_at(mw[(oc*b+k)*3+l/4],l%4)*byte_at(mp[(k*n+p)*3+l/4],l%4);
                mr[oc*n+p]=(uint32_t)s;
            }
            mdots=o*n*b;cycles=mdots*3;status=2;return;
        }
        abort();
    default:abort();
    }
}
#endif
static uint32_t hash(const int8_t *p,uint32_t n) {
    uint32_t h=2166136261u;for(uint32_t i=0;i<n;++i) h=(h^(uint8_t)p[i])*16777619u;return h;
}
static int8_t sample(uint32_t i,uint32_t pattern) {
    if(pattern==0) return 0;
    if(pattern==1) return (i&1)?127:-128;
    if(pattern==2) return -128;
    if(pattern==3) return 127;
    if(pattern==4) return (int8_t)(i*73u+19u);
    return (int8_t)((i*1103515245u+12345u)>>17);
}
static int run_case(uint32_t c,uint32_t p,uint32_t o,uint32_t stride,uint32_t pattern) {
    const uint32_t plane=32,first=3,ws=c+3;
    for(uint32_t i=0;i<sizeof(input);++i) input[i]=sample(i,pattern);
    for(uint32_t i=0;i<sizeof(weights);++i) weights[i]=sample(i*3+11,pattern);
    uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights));
    for(uint32_t i=0;i<34;++i) output[i]=0x12345678;
    uint32_t clocks=0;
    if(ai_run_1x1_block(input+8,plane,first,stride,c,weights+8,ws,p,o,output+1,&clocks)!=0) return 1;
    if(clocks!=3u*((c+8u)/9u)*p*o) return 2;
    for(uint32_t oc=0;oc<o;++oc) for(uint32_t px=0;px<p;++px) {
        int32_t s=0;
        for(uint32_t ch=0;ch<c;++ch) s+=(int32_t)input[8+ch*plane+first+px*stride]*(int32_t)weights[8+oc*ws+ch];
        if(output[1+oc*p+px]!=s) return 3;
    }
    for(uint32_t i=0;i<34;++i) if((i==0 || i>=1+o*p) && output[i]!=0x12345678) return 4;
    if(hash(input,sizeof(input))!=ih || hash(weights,sizeof(weights))!=wh) return 5;
    return 0;
}
#ifndef BLOCK_HOST_TEST
static uint64_t benchmark_legacy(void) {
    const uint32_t c=224,b=25,p=8,o=4;
    for(uint32_t oc=0;oc<o;++oc) for(uint32_t k=0;k<b;++k) for(uint32_t word=0;word<3;++word) {
        uint32_t v=0;
        for(uint32_t lane=0;lane<4;++lane) {uint32_t ch=k*9+word*4+lane;if(word*4+lane<9 && ch<c) v|=(uint32_t)(uint8_t)weights[8+oc*227+ch]<<(lane*8);}
        packed_w[(oc*b+k)*3+word]=v;
    }
    for(uint32_t k=0;k<b;++k) for(uint32_t px=0;px<p;++px) for(uint32_t word=0;word<3;++word) {
        uint32_t v=0;
        for(uint32_t lane=0;lane<4;++lane) {uint32_t ch=k*9+word*4+lane;if(word*4+lane<9 && ch<c) v|=(uint32_t)(uint8_t)input[8+ch*32+3+px*2]<<(lane*8);}
        packed_p[(k*p+px)*3+word]=v;
    }
    uint64_t t=rdcycle64();
    AI_BIAS=0;
    for(uint32_t oc=0;oc<o;++oc) {
        for(uint32_t px=0;px<p;++px) output[1+oc*p+px]=0;
        for(uint32_t k=0;k<b;++k) {
            const uint32_t *v=packed_w+(oc*b+k)*3;AI_WGT0=v[0];AI_WGT1=v[1];AI_WGT2=v[2];
            for(uint32_t px=0;px<p;++px) {
                v=packed_p+(k*p+px)*3;AI_PIX0=v[0];AI_PIX1=v[1];AI_PIX2=v[2];AI_CTRL=1;
                while(!(AI_CTRL&AI_DONE)) {} output[1+oc*p+px]+=(int32_t)AI_ACCUM;
            }
        }
    }
    return rdcycle64()-t;
}
static int benchmark(void) {
    uint64_t legacy=benchmark_legacy();int32_t expected[32];
    for(uint32_t i=0;i<32;++i) expected[i]=output[i+1];
    // Same already-packed payloads: includes block uploads/start/wait/readback,
    // excludes CHW packing from BOTH paths; not a complete production layer.
    uint64_t t=rdcycle64();AI_BLOCK_WRITE(AI_BLOCK_CTRL,4);AI_BLOCK_WRITE(AI_BLOCK_WADDR,0);
    for(uint32_t i=0;i<300;++i) AI_BLOCK_WRITE(AI_BLOCK_WDATA,packed_w[i]);
    AI_BLOCK_WRITE(AI_BLOCK_PADDR,0);
    for(uint32_t i=0;i<600;++i) AI_BLOCK_WRITE(AI_BLOCK_PDATA,packed_p[i]);
    AI_BLOCK_WRITE(AI_BLOCK_SHAPE,8u|(4u<<4)|(25u<<8)|(8u<<16));AI_BLOCK_WRITE(AI_BLOCK_CTRL,1);
    while(!(AI_BLOCK_READ(AI_BLOCK_CTRL)&2)) {}
    AI_BLOCK_WRITE(AI_BLOCK_RADDR,0);
    for(uint32_t i=0;i<32;++i) output[i+1]=(int32_t)AI_BLOCK_READ(AI_BLOCK_RDATA);
    uint64_t tile=rdcycle64()-t;
    if(AI_BLOCK_READ(AI_BLOCK_CTRL)!=2 || AI_BLOCK_READ(AI_BLOCK_DOTS)!=800) return 10;
    for(uint32_t i=0;i<32;++i) if(output[i+1]!=expected[i]) return 11;
    uart_puts("A01_KERNEL legacy_cycles=");uart_putdec((uint32_t)legacy);
    uart_puts(" block_cycles=");uart_putdec((uint32_t)tile);
    uart_puts(" engine_cycles=");uart_putdec(AI_BLOCK_READ(AI_BLOCK_CYCLES));uart_putc('\n');
    return 0;
}
#endif
int main(void) {
    static const uint32_t channels[]={1,4,8,9,10,17,18,19,32,64,223,224};
    uint32_t cases=0,fail=0;
#ifdef BLOCK_HOST_TEST
    uint32_t guards=0;
    for(uint32_t ci=0;ci<12;++ci) for(uint32_t p=1;p<=8;p+=(p==1?2:5))
    for(uint32_t o=1;o<=4;o+=(o==1?2:1)) for(uint32_t st=1;st<=2;++st) for(uint32_t pat=0;pat<6;++pat) {
        fail=run_case(channels[ci],p,o,st,pat);if(fail) goto finish;++cases;
    }
    uint32_t count=transactions;
#define REJECT(...) do {if(ai_run_1x1_block(__VA_ARGS__)!=AI_BLOCK_BAD_SHAPE || transactions!=count) {fail=20;goto finish;} ++guards;} while(0)
    REJECT(0,0,0,0,0,0,0,0,0,0,0);
    REJECT(input,32,0,1,0,weights,1,1,1,output,0);
    REJECT(input,32,0,1,225,weights,225,1,1,output,0);
    REJECT(input,32,0,1,1,weights,1,0,1,output,0);
    REJECT(input,32,0,1,1,weights,1,9,1,output,0);
    REJECT(input,32,0,1,1,weights,1,1,0,output,0);
    REJECT(input,32,0,1,1,weights,1,1,5,output,0);
    REJECT(input,0,0,1,1,weights,1,1,1,output,0);
    REJECT(input,32,0,0,1,weights,1,1,1,output,0);
    REJECT(input,32,32,1,1,weights,1,1,1,output,0);
    REJECT(input,32,30,2,1,weights,1,2,1,output,0);
    REJECT(input,32,0,1,1,weights,0,1,1,output,0);
    REJECT(input,UINT32_MAX,0,1,2,weights,2,1,1,output,0);
    REJECT(input,32,0,1,1,weights,UINT32_MAX,1,4,output,0);
    REJECT(input,32,0,1,1,0,1,1,1,output,0);
    REJECT(input,32,0,1,1,weights,1,1,1,0,0);
#undef REJECT
    mode=1;if(ai_run_1x1_block(input,32,0,1,1,weights,1,1,1,output,0)!=AI_BLOCK_UNSUPPORTED) {fail=21;goto finish;}
    mode=2;if(ai_run_1x1_block(input,32,0,1,1,weights,1,1,1,output,0)!=AI_BLOCK_TIMEOUT) {fail=22;goto finish;}
    mode=3;if(ai_run_1x1_block(input,32,0,1,1,weights,1,1,1,output,0)!=AI_BLOCK_HW_ERROR) {fail=23;goto finish;}
    mode=4;if(ai_run_1x1_block(input,32,0,1,1,weights,1,1,1,output,0)!=AI_BLOCK_HW_ERROR) {fail=24;goto finish;}
#else
    uart_init(CLK_HZ,BAUD);
#ifdef AI_BLOCK_BOARD_DDR
    uart_puts("A02_BLOCK ID=0x");uart_puthex(AI_BLOCK_READ(AI_BLOCK_REG_ID));uart_putc('\n');
#endif
    for(uint32_t i=0;i<48;++i) {fail=run_case(channels[i/4],i%4==3?8:1+i%3,i%4+1,1+i%2,i%6);if(fail) goto finish;++cases;}
    fail=benchmark();
#endif
finish:
#ifdef BLOCK_HOST_TEST
    printf("A01_DRIVER cases=%u guards=%u result=%s code=%u\n",cases,guards,fail?"FAIL":"PASS",fail);
#else
    uart_puts("A01_DRIVER cases=");uart_putdec(cases);uart_puts(" code=");uart_putdec(fail);uart_putc('\n');
    block_test_result=fail?fail+1:1;
#endif
    return (int)fail;
}
