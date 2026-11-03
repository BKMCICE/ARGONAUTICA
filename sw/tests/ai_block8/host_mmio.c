/* Strict host transport model, not an RTL substitute. Scalar test references
 * read CHW tensors independently; real RV32/RTL validates this model's limits. */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "host_mmio.h"
#include "../../common/ai_mac_block.h"
static uint32_t w[600],p[600],r[64],wi,pi,ri,shape,status,mode,words;
static unsigned char wvalid[600],pvalid[600];
uint32_t a33_raw_reads;
uint32_t a33_starts,a33_weight_words,a33_pixel_words,a33_reads,a33_writes;
extern uint32_t host_ai_calls;
void a33_reset(unsigned value) {
    a33_raw_reads=0;
    mode=value;wi=pi=ri=shape=status=words=0;
    a33_starts=a33_weight_words=a33_pixel_words=a33_reads=a33_writes=0;
    memset(wvalid,0,sizeof(wvalid));memset(pvalid,0,sizeof(pvalid));
    memset(w,0xa5,sizeof(w));memset(p,0xa5,sizeof(p));
}
uint32_t a33_read(uint32_t off) {
    ++a33_reads;
    if(off==0x28)return mode==7?0:0x41333331u;
    if(off==AI_BLOCK_REG_ID) return mode==1 ? 0:AI_BLOCK_ID;
    if(off==AI_BLOCK_CTRL) return mode==2 ? 1:status;
    if(off==AI_BLOCK_RDATA) {
        ++a33_raw_reads;
        if(!(status&2) || (status&1) || ri>=words) abort();
        uint32_t value=r[ri++];if(mode==5) status|=4;return value;
    }
    abort();
}
void a33_write(uint32_t off,uint32_t value) {
    ++a33_writes;
    if(status&1) abort();
    switch(off) {
    case AI_BLOCK_WADDR:wi=value*3u;if(wi>=(mode==7?300u:600u)) abort();return;
    case AI_BLOCK_PADDR:pi=value*3u;if(pi>=600) abort();return;
    case AI_BLOCK_RADDR:if(value>=(mode==7?32u:64u))abort();ri=value;return;
    case AI_BLOCK_WDATA:if(wi>=(mode==7?300u:600u)) abort();wvalid[wi]=1;w[wi++]=value;++a33_weight_words;return;
    case AI_BLOCK_PDATA:if(pi>=600) abort();pvalid[pi]=1;p[pi++]=value;++a33_pixel_words;return;
    case AI_BLOCK_SHAPE:shape=value;return;
    case AI_BLOCK_CTRL:
        if(value==4) {status=0;return;}
        if(value!=1) abort();
        ++a33_starts;
        if(mode==3 || (mode==6 && a33_starts==2)) {status=0;return;}
        if(mode==4) {status=6;return;}
        {
            unsigned n=shape&15,o=(shape>>4)&15,b=(shape>>8)&63,last=(shape>>16)&15;
            if(!n || n>8 || !o || o>(mode==7?4u:8u) || !b || b>25 || !last || last>9 || (b==25 && last>8)) abort();
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
