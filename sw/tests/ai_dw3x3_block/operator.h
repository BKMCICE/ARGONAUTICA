/* A10 isolated prototype. Include after YoloLayer/apply_q24/clip8.
 * Own the AI unit for the complete call. A failed later tile can leave partial
 * output: discard it. Only shape/unsupported before writes permit fallback.
 * Fixed-model Q24/bias range follows the existing YOLO operator contract. */
#ifndef A10_DW3X3_BLOCK_OPERATOR_H
#define A10_DW3X3_BLOCK_OPERATOR_H
#include "../../common/ai_mac_block.h"
#include "../../common/ai_mac_prepack.h"
static int a10_span(const void *p,uint32_t n) {
    return p && n && (uintptr_t)p<=UINTPTR_MAX-(n-1u);
}
static int a10_disjoint(const void *a,uint32_t na,const void *b,uint32_t nb) {
    uintptr_t x=(uintptr_t)a,y=(uintptr_t)b;
    return x<y ? na<=y-x : nb<=x-y;
}
static inline void a10_pack3(const int8_t *input,uint32_t h,uint32_t w,
                            int32_t y,int32_t x,uint32_t p[3]) {
    p[0]=p[1]=p[2]=0;
    if(h>=3 && w>=3 && y>=0 && x>=0 && (uint32_t)y<=h-3 && (uint32_t)x<=w-3) {
        const int8_t *r0=input+(uint32_t)y*w+(uint32_t)x,*r1=r0+w,*r2=r1+w;
        p[0]=(uint32_t)(uint8_t)r0[0]|(uint32_t)(uint8_t)r0[1]<<8|
             (uint32_t)(uint8_t)r0[2]<<16|(uint32_t)(uint8_t)r1[0]<<24;
        p[1]=(uint32_t)(uint8_t)r1[1]|(uint32_t)(uint8_t)r1[2]<<8|
             (uint32_t)(uint8_t)r2[0]<<16|(uint32_t)(uint8_t)r2[1]<<24;
        p[2]=(uint32_t)(uint8_t)r2[2];
    } else {
        for(uint32_t ky=0;ky<3;++ky) for(uint32_t kx=0;kx<3;++kx) {
            int32_t yy=y+(int32_t)ky,xx=x+(int32_t)kx;uint32_t lane=ky*3+kx;
            if(yy>=0 && yy<(int32_t)h && xx>=0 && xx<(int32_t)w)
                p[lane/4]|=(uint32_t)(uint8_t)input[(uint32_t)yy*w+(uint32_t)xx]<<(8*(lane%4));
        }
    }
}
__attribute__((noinline)) static int a10_conv3x3_block(const YoloLayer *l,
    const int8_t *input,int8_t *output,const int8_t *weights,const int32_t *params) {
    if(!l || l->kind!=YOLO_CONV || l->size!=3 || !l->ic || l->ic!=l->oc ||
       l->groups!=l->ic || !l->stride || l->stride>INT32_MAX || l->pad>2 ||
       !l->ih || !l->iw || !l->oh || !l->ow || l->ih>INT32_MAX-4u || l->iw>INT32_MAX-4u ||
       l->ih+2*l->pad<3 || l->iw+2*l->pad<3 ||
       l->oh-1u>(l->ih+2*l->pad-3u)/l->stride ||
       l->ow-1u>(l->iw+2*l->pad-3u)/l->stride ||
       l->iw>UINT32_MAX/l->ih || l->ow>UINT32_MAX/l->oh) return AI_BLOCK_BAD_SHAPE;
    uint32_t plane=l->ih*l->iw,out_plane=l->oh*l->ow;
    if(l->ic>UINT32_MAX/plane || l->oc>UINT32_MAX/out_plane || l->oc>UINT32_MAX/9u)
        return AI_BLOCK_BAD_SHAPE;
    uint32_t ni=l->ic*plane,no=l->oc*out_plane,nw=l->oc*9,np=l->oc*8;
    if(!a10_span(input,ni) || !a10_span(output,no) || !a10_span(weights,nw) || !a10_span(params,np) ||
       !a10_disjoint(output,no,input,ni) || !a10_disjoint(output,no,weights,nw) ||
       !a10_disjoint(output,no,params,np)) return AI_BLOCK_BAD_SHAPE;
    if(AI_BLOCK_READ(AI_BLOCK_REG_ID)!=AI_BLOCK_ID) return AI_BLOCK_UNSUPPORTED;
    if(AI_BLOCK_READ(AI_BLOCK_CTRL)&1u) return AI_BLOCK_HW_ERROR;
    uint32_t p[3];int32_t acc[8];
    for(uint32_t oc=0;oc<l->oc;++oc) {
        AI_BLOCK_WRITE(AI_BLOCK_CTRL,4u);AI_BLOCK_WRITE(AI_BLOCK_WADDR,0);
        ai_pack_1x1_weights(weights+oc*9u,9,p);
        for(uint32_t word=0;word<3;++word) AI_BLOCK_WRITE(AI_BLOCK_WDATA,p[word]);
        const int8_t *channel=input+oc*plane;
        for(uint32_t oy=0;oy<l->oh;++oy) for(uint32_t ox=0;ox<l->ow;) {
            uint32_t pixels=l->ow-ox;if(pixels>8) pixels=8;
            AI_BLOCK_WRITE(AI_BLOCK_CTRL,4u);AI_BLOCK_WRITE(AI_BLOCK_PADDR,0);
            for(uint32_t px=0;px<pixels;++px) {
                a10_pack3(channel,l->ih,l->iw,(int32_t)(oy*l->stride)-(int32_t)l->pad,
                    (int32_t)((ox+px)*l->stride)-(int32_t)l->pad,p);
                for(uint32_t word=0;word<3;++word) AI_BLOCK_WRITE(AI_BLOCK_PDATA,p[word]);
            }
            AI_BLOCK_WRITE(AI_BLOCK_SHAPE,pixels|(1u<<4)|(1u<<8)|(9u<<16));
            AI_BLOCK_WRITE(AI_BLOCK_CTRL,1u);
            uint32_t status=0,polls=0;
            do {status=AI_BLOCK_READ(AI_BLOCK_CTRL);++polls;} while(!(status&2u) && polls<100000u);
            if(!(status&2u)) return AI_BLOCK_TIMEOUT;
            if(status&5u) return AI_BLOCK_HW_ERROR;
            AI_BLOCK_WRITE(AI_BLOCK_RADDR,0);
            for(uint32_t px=0;px<pixels;++px) acc[px]=(int32_t)AI_BLOCK_READ(AI_BLOCK_RDATA);
            if(AI_BLOCK_READ(AI_BLOCK_CTRL)&4u) return AI_BLOCK_HW_ERROR;
            for(uint32_t px=0;px<pixels;++px) {
                int32_t v=apply_q24(acc[px],params[oc*2])+params[oc*2+1];
                if(l->leaky && v<0) v=apply_q24(v,YOLO_LEAKY_Q24);
                output[oc*out_plane+oy*l->ow+ox+px]=clip8(v);
            }
            ox+=pixels;
        }
    }
    return AI_BLOCK_OK;
}
#endif
