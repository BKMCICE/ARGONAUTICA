/* Strict host transport model, not an RTL substitute. Scalar test references
 * read CHW tensors independently; real RV32/RTL validates this model's limits. */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "host_mmio.h"
#include "../../common/ai_mac_block.h"
#ifndef HOST_AI_BLOCK8
#define HOST_AI_BLOCK8 0
#endif
static uint32_t w[HOST_AI_BLOCK8 ? 600 : 300],p[600],r[HOST_AI_BLOCK8 ? 64 : 32],wi,pi,ri,shape,status,mode,words;
static unsigned char wvalid[HOST_AI_BLOCK8 ? 600 : 300],pvalid[600];
static unsigned block8_enabled = HOST_AI_BLOCK8;
void a03_set_block8(unsigned enabled) {
    if (enabled && !HOST_AI_BLOCK8) abort();
    block8_enabled = enabled != 0;
}
uint32_t a03_starts,a03_weight_words,a03_pixel_words,a03_reads,a03_writes;
extern uint32_t host_ai_calls;
static void __attribute__((constructor)) initialize_model(void) {
    const char *value=getenv("A03_HOST_MISSING");
    if (getenv("A45_HOST_OLD_CAP")) block8_enabled=0;
    a03_reset(value && value[0]=='1' ? 1:0);
}
static void __attribute__((destructor)) report_model(void) {
    if(getenv("A03_HOST_STATS"))
        fprintf(stderr,"A03_HOST_MMIO tasks=%u weight_words=%u pixel_words=%u reads=%u writes=%u\n",
            a03_starts,a03_weight_words,a03_pixel_words,a03_reads,a03_writes);
#if YOLO_BLOCK_INPUT_CACHE
    extern uint32_t host_block_cached_groups,host_block_cached_pixels;
    if(getenv("A03_HOST_STATS"))
        fprintf(stderr,"A07_HOST_CACHE groups=%u pixels=%u\n",host_block_cached_groups,host_block_cached_pixels);
#endif
#if YOLO_DW3X3_ROLLING
    extern uint32_t host_dw3_rolling_calls;
    if(getenv("A03_HOST_STATS"))
        fprintf(stderr,"A16_HOST_DW3_ROLLING calls=%u\n",host_dw3_rolling_calls);
#endif
}
void a03_reset(unsigned value) {
    mode=value;wi=pi=ri=shape=status=words=0;
    a03_starts=a03_weight_words=a03_pixel_words=a03_reads=a03_writes=0;
    memset(wvalid,0,sizeof(wvalid));memset(pvalid,0,sizeof(pvalid));
    memset(w,0xa5,sizeof(w));memset(p,0xa5,sizeof(p));
}
uint32_t a03_read(uint32_t off) {
    ++a03_reads;
    if(off==0x28u) return block8_enabled ? 0x41333331u : 0u;
    if(off==AI_BLOCK_REG_ID) return mode==1 ? 0:AI_BLOCK_ID;
    if(off==AI_BLOCK_CTRL) return mode==2 ? 1:status;
    if(off==AI_BLOCK_RDATA) {
        if(!(status&2) || (status&1) || ri>=words) abort();
        uint32_t value=r[ri++];if(mode==5) status|=4;return value;
    }
    abort();
}
void a03_write(uint32_t off,uint32_t value) {
    ++a03_writes;
    if(status&1) abort();
    switch(off) {
    case AI_BLOCK_WADDR:wi=value*3u;if(wi>=(block8_enabled?600u:300u)) abort();return;
    case AI_BLOCK_PADDR:pi=value*3u;if(pi>=600) abort();return;
    case AI_BLOCK_RADDR:if(value>=(block8_enabled?64u:32u))abort();ri=value;return;
    case AI_BLOCK_WDATA:if(wi>=(block8_enabled?600u:300u)) abort();wvalid[wi]=1;w[wi++]=value;++a03_weight_words;return;
    case AI_BLOCK_PDATA:if(pi>=600) abort();pvalid[pi]=1;p[pi++]=value;++a03_pixel_words;return;
    case AI_BLOCK_SHAPE:shape=value;return;
    case AI_BLOCK_CTRL:
        if(value==4) {status=0;return;}
        if(value!=1) abort();
        ++a03_starts;
        if(mode==3 || (mode==6 && a03_starts==2)) {status=0;return;}
        if(mode==4) {status=6;return;}
        {
            unsigned n=shape&15,o=(shape>>4)&15,b=(shape>>8)&63,last=(shape>>16)&15;
            if(!n || n>8 || !o || o>(block8_enabled?8u:4u) || !b || b>25 || !last || last>9 || (b==25 && last>8)) abort();
            for(unsigned i=0;i<o*b*3;++i) if(!wvalid[i]) abort();
            for(unsigned i=0;i<b*n*3;++i) if(!pvalid[i]) abort();
            for(unsigned oc=0;oc<o;++oc) for(unsigned px=0;px<n;++px) {
                int32_t sum=0;
                for(unsigned c=0;c<(b-1)*9+last;++c) {
                    unsigned lane=c%9,word=lane/4,shift=8*(lane%4),k=c/9;
                    sum+=(int32_t)(int8_t)(w[(oc*b+k)*3+word]>>shift)*
                         (int32_t)(int8_t)(p[(k*n+px)*3+word]>>shift);
                }
                r[oc*n+px]=(uint32_t)sum;
            }
            host_ai_calls+=o*n*b;words=o*n;status=2;return;
        }
    default:abort();
    }
}
