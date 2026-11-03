/* Strict host transport model, not an RTL substitute. Scalar test references
 * read CHW tensors independently; real RV32/RTL validates this model's limits. */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "host_mmio.h"
#include "../../common/ai_mac_block.h"
static uint32_t w[600],p[600],r[64],wi,pi,ri,shape,status,mode,words;
static unsigned char wvalid[600],pvalid[600];
uint32_t a48_raw_reads,a48_packed_reads,a48_post_writes,a48_post_items;
static uint32_t qm[8],qb[8],qpacked[16],qi,qri,qwords,qenabled,qleaky,qmv,qbv;
static int32_t qscale(int32_t x,int32_t m){int64_t product=(int64_t)x*m;
 int64_t n=((product<0?-product:product)+8388608)/16777216;
 return(int32_t)(product<0?-n:n);}
static int post(unsigned n,unsigned o){
 qwords=qri=0;
 for(unsigned oc=0;oc<o;++oc){
  if(!(qmv&(1u<<oc))||!(qbv&(1u<<oc)))return 1;
  for(unsigned p=0;p<n;p+=4){uint32_t word=0;
   for(unsigned b=0;b<4&&p+b<n;++b){int64_t product=(int64_t)(int32_t)r[oc*n+p+b]*(int32_t)qm[oc];
    int64_t scaled=((product<0?-product:product)+8388608)/16777216;if(product<0)scaled=-scaled;
    if(scaled< -2147483647LL||scaled>2147483647LL)return 1;
    int64_t wide=scaled+(int32_t)qb[oc];if(wide< -2147483648LL||wide>2147483647LL)return 1;
    int32_t v=(int32_t)wide;if(qleaky&&v<0)v=qscale(v,1677722);
    if(v>127)v=127;if(v< -127)v=-127;
    word|=(uint32_t)(uint8_t)v<<(8*b);++a48_post_items;
   }qpacked[qwords++]=word;
  }
 }return 0;
}
uint32_t a48_starts,a48_weight_words,a48_pixel_words,a48_reads,a48_writes;
extern uint32_t host_ai_calls;
void a48_reset(unsigned value) {
    qi=qri=qwords=qenabled=qleaky=qmv=qbv=0;
    a48_raw_reads=a48_packed_reads=a48_post_writes=a48_post_items=0;
    mode=value;wi=pi=ri=shape=status=words=0;
    a48_starts=a48_weight_words=a48_pixel_words=a48_reads=a48_writes=0;
    memset(wvalid,0,sizeof(wvalid));memset(pvalid,0,sizeof(pvalid));
    memset(w,0xa5,sizeof(w));memset(p,0xa5,sizeof(p));
}
uint32_t a48_read(uint32_t off) {
    ++a48_reads;
    if(off==0x28)return mode==8?0:0x41333331u;
    if(off==0x2c)return mode==7||mode==8?0:0x41343831u;
    if(off==0x220){if(!(status&2)||(status&1)||qri>=qwords)abort();
        ++a48_packed_reads;uint32_t v=qpacked[qri++];if(mode==5)status|=4;return v;}
    if(off==AI_BLOCK_REG_ID) return mode==1 ? 0:AI_BLOCK_ID;
    if(off==AI_BLOCK_CTRL) return mode==2 ? 1:status;
    if(off==AI_BLOCK_RDATA) {
        ++a48_raw_reads;
        if(!(status&2) || (status&1) || ri>=words) abort();
        uint32_t value=r[ri++];if(mode==5) status|=4;return value;
    }
    abort();
}
void a48_write(uint32_t off,uint32_t value) {
    ++a48_writes;
    if(status&1) abort();
    if(off>=0x200&&off<0x300){++a48_post_writes;
        switch(off){
        case 0x204:if(value>3)abort();qenabled=value&1;qleaky=(value>>1)&1;qmv=qbv=qwords=qri=0;return;
        case 0x208:if(value>=8)abort();qi=value;qmv=qbv=0;return;
        case 0x20c:if(qi>=8)abort();qm[qi]=value;qmv|=1u<<qi;qbv&=~(1u<<qi);return;
        case 0x210:if(qi>=8||!(qmv&(1u<<qi)))abort();qb[qi]=value;qbv|=1u<<qi++;return;
        case 0x21c:if(value>=16)abort();qri=value;return;
        default:abort();
        }
    }
    switch(off) {
    case AI_BLOCK_WADDR:wi=value*3u;if(wi>=(mode==8?300u:600u)) abort();return;
    case AI_BLOCK_PADDR:pi=value*3u;if(pi>=600) abort();return;
    case AI_BLOCK_RADDR:ri=value;return;
    case AI_BLOCK_WDATA:if(wi>=(mode==8?300u:600u)) abort();wvalid[wi]=1;w[wi++]=value;++a48_weight_words;return;
    case AI_BLOCK_PDATA:if(pi>=600) abort();pvalid[pi]=1;p[pi++]=value;++a48_pixel_words;return;
    case AI_BLOCK_SHAPE:shape=value;return;
    case AI_BLOCK_CTRL:
        if(value==4) {status=0;return;}
        if(value!=1) abort();
        ++a48_starts;
        if(mode==3 || (mode==6 && a48_starts==2)) {status=0;return;}
        if(mode==4) {status=6;return;}
        {
            unsigned n=shape&15,o=(shape>>4)&15,b=(shape>>8)&63,last=(shape>>16)&15;
            if(!n || n>8 || !o || o>(mode==8?4u:8u) || !b || b>25 || !last || last>9 || (b==25 && last>8)) abort();
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
            host_ai_calls+=o*n*b;words=o*n;status=2;
            if(qenabled&&post(n,o))status=6;return;
        }
    default:abort();
    }
}
