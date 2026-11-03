/* Native correctness only: actual production pool, isolated separable pool,
 * independent int64/division oracle. No RV32 timing or deployment claim. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#define main a93_unused_production_main
#include "../../yolo_fixed/main.c"
#undef main
#include "../ai_pool_separable_board/diag.h"
unsigned a97_fast(void);unsigned a97_fallback(void);int a97_raw(const YoloLayer*,const int8_t*,int8_t*,int8_t*,uint32_t);
static unsigned checks,cases,guards;
static void check(int ok){++checks;if(!ok){fprintf(stderr,"A96_WRAPPED_FAIL check=%u case=%u\n",checks,cases);exit(1);}}
static int8_t oracle(int32_t v){
    int64_t p=(int64_t)v*29567173;
    int64_t n=((p<0?-p:p)+8388608)/16777216;
    if(p<0)n=-n;
    return n>127?127:n< -127?-127:(int8_t)n;
}
static int8_t input[4800+32],saved[4800+32],reference[4800+32],candidate[4800+32],scratch[100+32],placebo[4800+32];
static uint32_t rng=0x9263a17u;
static uint32_t next(void){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;return rng;}
static void one(const YoloLayer *l,unsigned pattern,unsigned off){
    memset(input,0x51,sizeof(input));
    for(unsigned i=0;i<4800;++i)input[8+off+i]=pattern<256?(int8_t)(pattern-128):pattern==256?(i%2?127:-128):pattern==257?(i%10==0?127:-128):pattern==258?(i%100==99?127:-128):(int8_t)next();
    memcpy(saved,input,sizeof(input));memset(reference,0x5a,sizeof(reference));memset(candidate,0x5a,sizeof(candidate));memset(scratch,0x33,sizeof(scratch));
    check(a96_control(l,input+8+off,reference+8+off)==0);
    memset(placebo,0x5a,sizeof(placebo));check(a96_placebo(l,input+8+off,placebo+8+off)==0);check(memcmp(reference,placebo,sizeof(reference))==0);
    check(a96_candidate(l,input+8+off,candidate+8+off,scratch+8+off,100)==0);
    check(memcmp(reference,candidate,sizeof(reference))==0);
    check(memcmp(input,saved,sizeof(input))==0);
    for(unsigned i=0;i<8+off;++i)check(scratch[i]==0x33);
    for(unsigned i=108+off;i<sizeof(scratch);++i)check(scratch[i]==0x33);
    for(unsigned c=0;c<48;++c)for(unsigned y=0;y<10;++y)for(unsigned x=0;x<10;++x){
        int best=-127;
        for(unsigned ky=0;ky<l->size;++ky)for(unsigned kx=0;kx<l->size;++kx){
            int yy=(int)y+(int)ky-(int)l->pad,xx=(int)x+(int)kx-(int)l->pad;
            if(yy>=0&&yy<10&&xx>=0&&xx<10){int v=input[8+off+c*100+(unsigned)yy*10+(unsigned)xx];if(v>best)best=v;}
        }
        check(candidate[8+off+(c*10+y)*10+x]==oracle(best));
    }
    ++cases;
}
static void invalid(void){
    YoloLayer base=yolo_layers[109];
    for(unsigned k=0;k<18;++k){
        YoloLayer l=base;const YoloLayer *lp=&l;const int8_t *ip=input;int8_t *op=candidate,*sp=scratch;unsigned n=100;
        switch(k){case 0:lp=0;break;case 1:ip=0;break;case 2:op=0;break;case 3:sp=0;break;case 4:n=99;break;case 5:l.kind=1;break;case 6:l.ih=9;break;case 7:l.iw=9;break;case 8:l.ic=47;break;case 9:l.oh=9;break;case 10:l.ow=9;break;case 11:l.oc=47;break;case 12:l.stride=2;break;case 13:l.size=1;break;case 14:l.size=7;break;case 15:l.pad=0;break;case 16:l.prev_q24=16777216;break;case 17:l.size=UINT32_MAX;break;}
        memset(candidate,0x5a,sizeof(candidate));memset(scratch,0x33,sizeof(scratch));
        check(a97_raw(lp,ip,op,sp,n)==-2);
        for(unsigned i=0;i<sizeof(candidate);++i)check(candidate[i]==0x5a);
        for(unsigned i=0;i<sizeof(scratch);++i)check(scratch[i]==0x33);
        ++guards;
    }
}
static unsigned fallbacks(void){
 const unsigned cases[10][8]={{1,1,1,1,1,0,1,1},{2,3,2,3,1,1,2,3},{7,11,3,3,2,1,4,6},{12,13,7,5,1,2,12,13},{10,10,48,7,1,3,10,10},{10,10,48,3,1,1,9,9},{10,10,48,3,2,1,5,5},{10,10,47,9,1,4,10,10},{10,10,48,9,1,3,10,10},{9,10,48,5,1,2,9,10}};
 const int32_t q[7]={29567173,16777216,0,1,-1,INT32_MAX,INT32_MIN};unsigned calls=0;
 for(unsigned a=0;a<10;++a)for(unsigned j=0;j<7;++j){YoloLayer l=yolo_layers[109];l.ih=cases[a][0];l.iw=cases[a][1];l.ic=l.oc=cases[a][2];l.size=cases[a][3];l.stride=cases[a][4];l.pad=cases[a][5];l.oh=cases[a][6];l.ow=cases[a][7];l.prev_q24=q[j];unsigned off=8+(a+j)%4;
  for(unsigned i=0;i<sizeof(input);++i)input[i]=(int8_t)next();memcpy(saved,input,sizeof(input));memset(reference,0x5a,sizeof(reference));memset(candidate,0x5a,sizeof(candidate));
  check(a96_control(&l,input+off,reference+off)==0);check(a96_candidate(&l,input+off,candidate+off,scratch,100)==0);check(memcmp(reference,candidate,sizeof(reference))==0);check(memcmp(saved,input,sizeof(input))==0);
  for(unsigned c=0;c<l.oc;++c)for(unsigned y=0;y<l.oh;++y)for(unsigned x=0;x<l.ow;++x){int best=-127;for(unsigned ky=0;ky<l.size;++ky)for(unsigned kx=0;kx<l.size;++kx){int yy=(int)(y*l.stride+ky)-(int)l.pad,xx=(int)(x*l.stride+kx)-(int)l.pad;if(yy>=0&&yy<(int)l.ih&&xx>=0&&xx<(int)l.iw){int v=input[off+(c*l.ih+(unsigned)yy)*l.iw+(unsigned)xx];if(v>best)best=v;}}int64_t p=(int64_t)best*l.prev_q24,n=((p<0?-p:p)+8388608)/16777216;if(p<0)n=-n;int8_t expected=n>127?127:n< -127?-127:n;check(candidate[off+(c*l.oh+y)*l.ow+x]==expected);}
  ++calls;
 }return calls;
}

int main(void){
    /* A deliberately wrong intermediate requantization must be detectable. */
    check(oracle(oracle(7))!=oracle(7));
    const unsigned idx[3]={109,111,113};invalid();
    for(unsigned j=0;j<3;++j){const YoloLayer *l=&yolo_layers[idx[j]];
        check(l->kind==YOLO_MAXPOOL&&l->size==(j==0?3:j==1?5:9));
        for(unsigned p=0;p<256;++p)one(l,p,p%4);
        for(unsigned p=256;p<320;++p)for(unsigned off=0;off<4;++off)one(l,p,off);
    }
    check(a97_fast()==1536);unsigned generic=fallbacks();check(generic==70&&a97_fallback()==70&&a97_fast()==1536);
    printf("A97_PRODUCTION_POOL_THREE_WAY_PASS cases=%u guards=%u checks=%u scratch_bytes=100 fallback=70\n",cases,guards,checks);return 0;
}
