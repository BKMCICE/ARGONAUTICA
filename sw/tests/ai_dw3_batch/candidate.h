/* Test-only operator. The unchanged production rolling implementation is the
 * control and the pre-write fallback. Tensor/parameter ownership is exclusive. */
#ifndef A53_CANDIDATE_H
#define A53_CANDIDATE_H
#include "transport.h"
__attribute__((noinline)) static int a53_batch_operator(const YoloLayer *l,const int8_t *input,
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
    if(A53_READ(0x300)!=A53_ID)return conv3x3_rolling(l,input,output,weights,params);
    if(A53_READ(0x304)&1)return -2; // do not steal another task
    uint32_t first=(l->pad+s-1)/s;if(first>l->ow)first=l->ow;
    uint32_t last=l->iw>=3?(l->iw-3+l->pad)/s+1:0;
    if(last>l->ow)last=l->ow;if(last<first)last=first;
    for(uint32_t c=0;c<l->oc;++c){
        const int8_t *channel=input+c*plane,*w=weights+c*9;
        int32_t mult=params[c*2],bias=params[c*2+1];
        ai_load_1x1_weights(w,9); // old border path shares the same resident weights
        A53_WRITE(0x304,2);A53_WRITE(0x314,0);
        for(uint32_t i=0;i<3;++i){
            uint32_t word=0;
            for(uint32_t j=0;j<4&&i*4+j<9;++j)word|=(uint32_t)(uint8_t)w[i*4+j]<<(8*j);
            A53_WRITE(0x318,word);
        }
        A53_WRITE(0x30c,(uint32_t)mult);A53_WRITE(0x310,(uint32_t)bias);
        for(uint32_t oy=0;oy<l->oh;++oy){
            int32_t y=(int32_t)(oy*s)-(int32_t)l->pad;
            int8_t *dest=output+c*op+oy*l->ow;
            uint32_t ox=0;
            if(y<0||l->ih<3||(uint32_t)y>l->ih-3||first==last){
                for(;ox<l->ow;++ox)dest[ox]=dw3_quant(ai_dot3x3_loaded(channel,l->ih,l->iw,y,
                    (int32_t)(ox*s)-(int32_t)l->pad),mult,bias,l->leaky);
                continue;
            }
            for(;ox<first;++ox)dest[ox]=dw3_quant(ai_dot3x3_loaded(channel,l->ih,l->iw,y,
                (int32_t)(ox*s)-(int32_t)l->pad),mult,bias,l->leaky);
            while(ox<last){
                uint32_t n=last-ox;if(n>8)n=8;
                uint32_t width=3+(n-1)*s;
                const int8_t *p=channel+(uint32_t)y*l->iw+ox*s-l->pad;
                A53_WRITE(0x304,4);A53_WRITE(0x308,n|((s-1)<<4)|((l->leaky!=0)<<5));
                for(uint32_t row=0;row<3;++row){
                    A53_WRITE(0x31c,row*5);
                    for(uint32_t col=0;col<width;col+=4){
                        uint32_t word=0;
                        for(uint32_t j=0;j<4&&col+j<width;++j)
                            word|=(uint32_t)(uint8_t)p[row*l->iw+col+j]<<(8*j);
                        A53_WRITE(0x320,word);
                    }
                }
                A53_WRITE(0x304,1);
                int rc=a53_wait();if(rc)return rc;
                if(A53_READ(0x330)!=n)return -5;
                for(uint32_t i=0;i<n;i+=4){
                    uint32_t word=A53_READ(0x32c);
                    for(uint32_t j=0;j<4&&i+j<n;++j)dest[ox+i+j]=(int8_t)(word>>(8*j));
                }
                // A late fault must not silently fall back or publish another batch.
                if(A53_READ(0x304)&4)return -2;
                ox+=n;
            }
            for(;ox<l->ow;++ox)dest[ox]=dw3_quant(ai_dot3x3_loaded(channel,l->ih,l->iw,y,
                (int32_t)(ox*s)-(int32_t)l->pad),mult,bias,l->leaky);
        }
    }
    A53_WRITE(0x304,2);
    return AI_BLOCK_OK;
}
#endif
