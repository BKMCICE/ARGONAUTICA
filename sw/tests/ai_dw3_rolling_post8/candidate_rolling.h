/* A89: same validated shape/tensor contract and 24-bit row rolling as the
 * accepted operator. Only the transport/quantization task boundary is new.
 * Caller owns AI, keeps descriptor and readonly inputs stable, and discards
 * the whole output layer on any failure after a task starts. */
#include "../../common/ai_mac_prepack.h"
#include "../../yolo_fixed/post8_word_store.h"
static inline void a89_border_pack(const int8_t *input,uint32_t h,uint32_t w,
    int32_t y,int32_t x,uint32_t p[3]){
    p[0]=p[1]=p[2]=0;
    for(uint32_t ky=0;ky<3;++ky)for(uint32_t kx=0;kx<3;++kx){
        int32_t yy=y+(int32_t)ky,xx=x+(int32_t)kx;
        uint32_t lane=ky*3+kx;
        if(yy>=0&&yy<(int32_t)h&&xx>=0&&xx<(int32_t)w)
            p[lane/4]|=(uint32_t)(uint8_t)input[(uint32_t)yy*w+(uint32_t)xx]<<(8*(lane%4));
    }
}
__attribute__((noinline)) static int a89_finish(int8_t *dest,uint32_t count){
    AI_BLOCK_WRITE(AI_BLOCK_SHAPE,count|(1u<<4)|(1u<<8)|(9u<<16));
    AI_BLOCK_WRITE(AI_BLOCK_CTRL,1u);
    uint32_t status=0,polls=0;
    do{status=AI_BLOCK_READ(AI_BLOCK_CTRL);++polls;}while(!(status&2u)&&polls<100000u);
    if(!(status&2u))return AI_BLOCK_TIMEOUT;
    if(status&5u)return AI_BLOCK_HW_ERROR;
    AI_BLOCK_WRITE(0x21cu,0u);
    for(uint32_t px=0;px<count;){
        uint32_t word=AI_BLOCK_READ(0x220u),n=count-px;if(n>4)n=4;
        post8_word_store(dest+px,word,n);px+=n;
    }
    if(AI_BLOCK_READ(AI_BLOCK_CTRL)&4u)return AI_BLOCK_HW_ERROR;
    return AI_BLOCK_OK;
}
/* The validator prefix is inserted mechanically from the production header. */
__attribute__((noinline)) static int a89_post8_rolling(const YoloLayer *l,const int8_t *input,
    int8_t *output,const int8_t *weights,const int32_t *params){
    if(!l||l->kind!=YOLO_CONV||l->size!=3||!l->ic||l->ic!=l->oc||l->groups!=l->ic||
       !l->stride||l->stride>2||l->pad>2||!l->ih||!l->iw||!l->oh||!l->ow||
       l->ih>INT32_MAX-4u||l->iw>INT32_MAX-4u||l->ih+2*l->pad<3||l->iw+2*l->pad<3||
       l->oh-1u>(l->ih+2*l->pad-3u)/l->stride||l->ow-1u>(l->iw+2*l->pad-3u)/l->stride||
       l->iw>UINT32_MAX/l->ih||l->ow>UINT32_MAX/l->oh)return AI_BLOCK_BAD_SHAPE;
    uint32_t plane=l->ih*l->iw,op=l->oh*l->ow,s=l->stride;
    if(l->ic>UINT32_MAX/plane||l->oc>UINT32_MAX/op||l->oc>UINT32_MAX/9u)return AI_BLOCK_BAD_SHAPE;
    uint32_t ni=l->ic*plane,no=l->oc*op,nw=l->oc*9,np=l->oc*8;
    if(!dw3_span(input,ni)||!dw3_span(output,no)||!dw3_span(weights,nw)||!dw3_span(params,np)||
       !dw3_disjoint(output,no,input,ni)||!dw3_disjoint(output,no,weights,nw)||
       !dw3_disjoint(output,no,params,np))return AI_BLOCK_BAD_SHAPE;

    uint32_t id=AI_BLOCK_READ(AI_BLOCK_REG_ID);
    /* Legacy-only RTL aliases 0x100 onto CTRL: idle is 0 or DONE(2).
     * Recognize both before writes; BUSY and unknown IDs remain fatal. */
    if(id!=AI_BLOCK_ID)return (id==0u||id==2u)?AI_BLOCK_UNSUPPORTED:AI_BLOCK_HW_ERROR;
    uint32_t post=AI_BLOCK_READ(0x2cu),raw=AI_BLOCK_READ(0x28u);
    if((post&&post!=0x41343831u)||(raw&&raw!=0x41333331u)||
       (post&&raw!=0x41333331u))return AI_BLOCK_HW_ERROR;
    if(!post)return AI_BLOCK_UNSUPPORTED;
    if((AI_BLOCK_READ(AI_BLOCK_CTRL)&1u)||(AI_BLOCK_READ(0u)&1u))return AI_BLOCK_HW_ERROR;
    AI_BLOCK_WRITE(0x204u,1u|(l->leaky?2u:0u));
    uint32_t first=(l->pad+s-1)/s;if(first>l->ow)first=l->ow;
    uint32_t last=l->iw>=3?(l->iw-3+l->pad)/s+1:0;
    if(last>l->ow)last=l->ow;if(last<first)last=first;
    for(uint32_t oc=0;oc<l->oc;++oc){
        uint32_t p[3];ai_pack_1x1_weights(weights+oc*9,9,p);
        AI_BLOCK_WRITE(AI_BLOCK_CTRL,4u);AI_BLOCK_WRITE(AI_BLOCK_WADDR,0u);
        for(uint32_t k=0;k<3;++k)AI_BLOCK_WRITE(AI_BLOCK_WDATA,p[k]);
        AI_BLOCK_WRITE(0x208u,0u);AI_BLOCK_WRITE(0x20cu,(uint32_t)params[oc*2]);
        AI_BLOCK_WRITE(0x210u,(uint32_t)params[oc*2+1]);
        const int8_t *channel=input+oc*plane;
        for(uint32_t oy=0;oy<l->oh;++oy){
            int32_t y=(int32_t)(oy*s)-(int32_t)l->pad;
            uint32_t inside=l->ih>=3&&l->iw>=3&&y>=0&&(uint32_t)y<=l->ih-3&&first<last;
            const int8_t *r0=0,*r1=0,*r2=0;uint32_t a=0,b=0,c=0;
            int8_t *dest=output+oc*op+oy*l->ow;
            for(uint32_t ox=0;ox<l->ow;){
                uint32_t count=l->ow-ox;if(count>8)count=8;
                AI_BLOCK_WRITE(AI_BLOCK_CTRL,4u);AI_BLOCK_WRITE(AI_BLOCK_PADDR,0u);
                for(uint32_t px=0;px<count;++px){
                    uint32_t x=ox+px;
                    if(inside&&x>=first&&x<last){
                        if(x==first){
                            r0=channel+(uint32_t)y*l->iw+x*s-l->pad;r1=r0+l->iw;r2=r1+l->iw;
                            a=dw3_row(r0);b=dw3_row(r1);c=dw3_row(r2);
                        }else if(s==1){
                            ++r0;++r1;++r2;
                            a=(a>>8)|(uint32_t)(uint8_t)r0[2]<<16;
                            b=(b>>8)|(uint32_t)(uint8_t)r1[2]<<16;
                            c=(c>>8)|(uint32_t)(uint8_t)r2[2]<<16;
                        }else{
                            r0+=2;r1+=2;r2+=2;
                            a=(a>>16)|(uint32_t)(uint8_t)r0[1]<<8|(uint32_t)(uint8_t)r0[2]<<16;
                            b=(b>>16)|(uint32_t)(uint8_t)r1[1]<<8|(uint32_t)(uint8_t)r1[2]<<16;
                            c=(c>>16)|(uint32_t)(uint8_t)r2[1]<<8|(uint32_t)(uint8_t)r2[2]<<16;
                        }
                        p[0]=a|(b<<24);p[1]=(b>>8)|(c<<16);p[2]=c>>16;
                    }else a89_border_pack(channel,l->ih,l->iw,y,(int32_t)(x*s)-(int32_t)l->pad,p);
                    for(uint32_t k=0;k<3;++k)AI_BLOCK_WRITE(AI_BLOCK_PDATA,p[k]);
                }
                int rc=a89_finish(dest+ox,count);if(rc)return rc;
                ox+=count;
            }
        }
    }
    AI_BLOCK_WRITE(0x204u,0u);
    return AI_BLOCK_OK;
}
