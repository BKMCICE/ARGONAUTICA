/* A24 prototype only; not included by the production application.
 * Exactly three CHW input channels, ordinary 3x3 convolution, groups=1.
 * The existing A02 engine consumes three nine-lane vectors per output.
 */
#ifndef A24_RGB3_BLOCK_H
#define A24_RGB3_BLOCK_H
#include "../../common/ai_mac_block.h"
static inline int rgb3_disjoint(const void *a,uint32_t an,const void *b,uint32_t bn)
{
    uintptr_t x=(uintptr_t)a,y=(uintptr_t)b;
    if(!an||!bn||x>UINTPTR_MAX-(an-1u)||y>UINTPTR_MAX-(bn-1u))return 0;
    return x<y?an<=y-x:bn<=x-y;
}
static inline void rgb3_pack(const int8_t *src,uint32_t ih,uint32_t iw,
    int32_t y,int32_t x,uint32_t p[3])
{
    if(y>=0&&x>=0&&(uint32_t)y+2u<ih&&(uint32_t)x+2u<iw){
        const uint8_t *v=(const uint8_t *)src+(uint32_t)y*iw+(uint32_t)x;
        p[0]=(uint32_t)v[0]|(uint32_t)v[1]<<8|(uint32_t)v[2]<<16|(uint32_t)v[iw]<<24;
        p[1]=(uint32_t)v[iw+1]|(uint32_t)v[iw+2]<<8|(uint32_t)v[2*iw]<<16|(uint32_t)v[2*iw+1]<<24;
        p[2]=v[2*iw+2];
    }else{
        p[0]=p[1]=p[2]=0;
        for(uint32_t ky=0;ky<3;++ky)for(uint32_t kx=0;kx<3;++kx){
            int32_t yy=y+(int32_t)ky,xx=x+(int32_t)kx;uint32_t lane=ky*3+kx;
            if(yy>=0&&xx>=0&&(uint32_t)yy<ih&&(uint32_t)xx<iw)
                p[lane>>2]|=(uint32_t)(uint8_t)src[(uint32_t)yy*iw+(uint32_t)xx]<<((lane&3u)*8);
        }
    }
}
__attribute__((noinline)) static int rgb3_block(const YoloLayer *l,
    const int8_t *input,int8_t *output,const int8_t *weights,const int32_t *params)
{
    if(!l||!input||!output||!weights||!params||l->kind!=YOLO_CONV||l->size!=3||
       l->groups!=1||l->ic!=3||!l->oc||!l->ih||!l->iw||!l->oh||!l->ow||
       (l->stride!=1&&l->stride!=2)||l->pad>2||l->ih>0x3fffffffu||l->iw>0x3fffffffu||
       l->ih+2*l->pad<3||l->iw+2*l->pad<3||
       l->oh-1>(l->ih+2*l->pad-3)/l->stride||
       l->ow-1>(l->iw+2*l->pad-3)/l->stride||
       l->iw>UINT32_MAX/l->ih||l->ow>UINT32_MAX/l->oh)return AI_BLOCK_BAD_SHAPE;
    uint32_t ip=l->ih*l->iw,op=l->oh*l->ow;
    if(ip>UINT32_MAX/3||l->oc>UINT32_MAX/op||l->oc>UINT32_MAX/27||l->oc>UINT32_MAX/8)
        return AI_BLOCK_BAD_SHAPE;
    if(!rgb3_disjoint(output,l->oc*op,input,3*ip)||
       !rgb3_disjoint(output,l->oc*op,weights,l->oc*27)||
       !rgb3_disjoint(output,l->oc*op,params,l->oc*8)||
       !rgb3_disjoint(output,l->oc*op,l,sizeof(*l)))return AI_BLOCK_BAD_SHAPE;
    if(AI_BLOCK_READ(AI_BLOCK_REG_ID)!=AI_BLOCK_ID)return AI_BLOCK_UNSUPPORTED;
    if(AI_BLOCK_READ(AI_BLOCK_CTRL)&1u)return AI_BLOCK_HW_ERROR;
    uint32_t packed[3];int32_t acc[32];
    for(uint32_t oc=0;oc<l->oc;oc+=4){
        uint32_t outputs=l->oc-oc;if(outputs>4)outputs=4;
        AI_BLOCK_WRITE(AI_BLOCK_CTRL,4u);AI_BLOCK_WRITE(AI_BLOCK_WADDR,0u);
        for(uint32_t ch=0;ch<outputs;++ch)for(uint32_t ic=0;ic<3;++ic){
            ai_pack_1x1_weights(weights+(oc+ch)*27+ic*9,9,packed);
            for(uint32_t k=0;k<3;++k)AI_BLOCK_WRITE(AI_BLOCK_WDATA,packed[k]);
        }
        for(uint32_t y=0;y<l->oh;++y)for(uint32_t x=0;x<l->ow;){
            uint32_t pixels=l->ow-x;if(pixels>8)pixels=8;
            AI_BLOCK_WRITE(AI_BLOCK_CTRL,4u);AI_BLOCK_WRITE(AI_BLOCK_PADDR,0u);
            for(uint32_t ic=0;ic<3;++ic)for(uint32_t p=0;p<pixels;++p){
                rgb3_pack(input+ic*ip,l->ih,l->iw,(int32_t)(y*l->stride)-(int32_t)l->pad,
                    (int32_t)((x+p)*l->stride)-(int32_t)l->pad,packed);
                AI_BLOCK_WRITE(AI_BLOCK_PDATA,packed[0]);AI_BLOCK_WRITE(AI_BLOCK_PDATA,packed[1]);
                AI_BLOCK_WRITE(AI_BLOCK_PDATA,packed[2]);
            }
            AI_BLOCK_WRITE(AI_BLOCK_SHAPE,pixels|(outputs<<4)|(3u<<8)|(9u<<16));
            AI_BLOCK_WRITE(AI_BLOCK_CTRL,1u);
            uint32_t status=0,polls=0;
            do{status=AI_BLOCK_READ(AI_BLOCK_CTRL);++polls;}while(!(status&2u)&&polls<100000u);
            if(!(status&2u))return AI_BLOCK_TIMEOUT;
            if(status&5u)return AI_BLOCK_HW_ERROR;
            AI_BLOCK_WRITE(AI_BLOCK_RADDR,0u);
            for(uint32_t i=0;i<outputs*pixels;++i)acc[i]=(int32_t)AI_BLOCK_READ(AI_BLOCK_RDATA);
            if(AI_BLOCK_READ(AI_BLOCK_CTRL)&4u)return AI_BLOCK_HW_ERROR;
            /* 27 signed INT8 products fit int32; Q24 remains signed int64. */
            for(uint32_t ch=0;ch<outputs;++ch){
                int32_t m=params[2*(oc+ch)],b=params[2*(oc+ch)+1];
                const int32_t *a=acc+ch*pixels;int8_t *d=output+(oc+ch)*op+y*l->ow+x;
                for(uint32_t p=0;p<pixels;++p){
                    int32_t v=apply_q24(*a++,m)+b;
                    if(l->leaky&&v<0)v=apply_q24(v,YOLO_LEAKY_Q24);
                    *d++=clip8(v);
                }
            }
            x+=pixels;
        }
    }
    return AI_BLOCK_OK;
}
#endif
