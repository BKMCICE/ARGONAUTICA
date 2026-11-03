/* Opt-in production rolling windows. Own the legacy dot unit, keep tensors
 * and parameters stable during the call; fixed-model Q24 ranges apply.
 * Uses classic resident-weight MMIO and the original DONE-wait contract. */
#ifndef A86_PLACEBO_ROLLING_H
#define A86_PLACEBO_ROLLING_H
#include "../../common/ai_mac_block.h"
#ifdef YOLO_HOST_TEST
uint32_t host_a86_placebo_dw3_rolling_calls;
#endif
static int a86_placebo_dw3_span(const void *p,uint32_t n){return p&&n&&(uintptr_t)p<=UINTPTR_MAX-(n-1u);}
static int a86_placebo_dw3_disjoint(const void *a,uint32_t na,const void *b,uint32_t nb){
    uintptr_t x=(uintptr_t)a,y=(uintptr_t)b;return x<y?na<=y-x:nb<=x-y;
}
static inline uint32_t a86_placebo_dw3_row(const int8_t *p){
    return (uint32_t)(uint8_t)p[0]|(uint32_t)(uint8_t)p[1]<<8|(uint32_t)(uint8_t)p[2]<<16;
}
static inline int32_t a86_placebo_dw3_dot(uint32_t r0,uint32_t r1,uint32_t r2){
    uint32_t p0=r0|(r1<<24),p1=(r1>>8)|(r2<<16),p2=r2>>16;
#ifdef YOLO_HOST_TEST
    return ai_dot9_packed(p0,p1,p2,host_resident_weights[0],host_resident_weights[1],host_resident_weights[2]);
#else
    AI_PIX0=p0;AI_PIX1=p1;AI_PIX2=p2;AI_CTRL=AI_START;
    while(!(AI_CTRL&AI_DONE)){}
    return (int32_t)AI_ACCUM;
#endif
}
static inline int8_t a86_placebo_dw3_quant(int32_t acc,int32_t mult,int32_t bias,uint32_t leaky){
    int32_t v=apply_q24(acc,mult)+bias;
    if(leaky&&v<0)v=apply_q24(v,YOLO_LEAKY_Q24);
    return clip8(v);
}
__attribute__((noinline)) static int a86_placebo_rolling(const YoloLayer *l,const int8_t *input,
    int8_t *output,const int8_t *weights,const int32_t *params){
    if(!l||l->kind!=YOLO_CONV||l->size!=3||!l->ic||l->ic!=l->oc||l->groups!=l->ic||
       !l->stride||l->stride>2||l->pad>2||!l->ih||!l->iw||!l->oh||!l->ow||
       l->ih>INT32_MAX-4u||l->iw>INT32_MAX-4u||l->ih+2*l->pad<3||l->iw+2*l->pad<3||
       l->oh-1u>(l->ih+2*l->pad-3u)/l->stride||l->ow-1u>(l->iw+2*l->pad-3u)/l->stride||
       l->iw>UINT32_MAX/l->ih||l->ow>UINT32_MAX/l->oh)return AI_BLOCK_BAD_SHAPE;
    uint32_t plane=l->ih*l->iw,op=l->oh*l->ow,s=l->stride;
    if(l->ic>UINT32_MAX/plane||l->oc>UINT32_MAX/op||l->oc>UINT32_MAX/9u)return AI_BLOCK_BAD_SHAPE;
    uint32_t ni=l->ic*plane,no=l->oc*op,nw=l->oc*9,np=l->oc*8;
    if(!a86_placebo_dw3_span(input,ni)||!a86_placebo_dw3_span(output,no)||!a86_placebo_dw3_span(weights,nw)||!a86_placebo_dw3_span(params,np)||
       !a86_placebo_dw3_disjoint(output,no,input,ni)||!a86_placebo_dw3_disjoint(output,no,weights,nw)||
       !a86_placebo_dw3_disjoint(output,no,params,np))return AI_BLOCK_BAD_SHAPE;
#ifdef YOLO_HOST_TEST
    ++host_a86_placebo_dw3_rolling_calls;
#endif
    uint32_t first=(l->pad+s-1)/s;if(first>l->ow)first=l->ow;
    uint32_t last=l->iw>=3?(l->iw-3+l->pad)/s+1:0;
    if(last>l->ow)last=l->ow;
    if(last<first)last=first;
    for(uint32_t oc=0;oc<l->oc;++oc){
        const int8_t *channel=input+oc*plane;int32_t mult=params[oc*2],bias=params[oc*2+1];
        ai_load_1x1_weights(weights+oc*9,9);
        for(uint32_t oy=0;oy<l->oh;++oy){
            int32_t y=(int32_t)(oy*s)-(int32_t)l->pad;
            int8_t *dest=output+oc*op+oy*l->ow;
            if(l->ih<3||l->iw<3||y<0||(uint32_t)y>l->ih-3||first==last){
                for(uint32_t ox=0;ox<l->ow;++ox)
                    dest[ox]=a86_placebo_dw3_quant(ai_dot3x3_loaded(channel,l->ih,l->iw,y,(int32_t)(ox*s)-(int32_t)l->pad),mult,bias,l->leaky);
                continue;
            }
            uint32_t ox=0;
            for(;ox<first;++ox)
                dest[ox]=a86_placebo_dw3_quant(ai_dot3x3_loaded(channel,l->ih,l->iw,y,(int32_t)(ox*s)-(int32_t)l->pad),mult,bias,l->leaky);
            const int8_t *r0=channel+(uint32_t)y*l->iw+ox*s-l->pad,*r1=r0+l->iw,*r2=r1+l->iw;
            uint32_t a=a86_placebo_dw3_row(r0),b=a86_placebo_dw3_row(r1),c=a86_placebo_dw3_row(r2);
            if(s==1){
                for(;;){
                    dest[ox]=a86_placebo_dw3_quant(a86_placebo_dw3_dot(a,b,c),mult,bias,l->leaky);
                    if(++ox==last)break;
                    ++r0;++r1;++r2;
                    a=(a>>8)|(uint32_t)(uint8_t)r0[2]<<16;
                    b=(b>>8)|(uint32_t)(uint8_t)r1[2]<<16;
                    c=(c>>8)|(uint32_t)(uint8_t)r2[2]<<16;
                }
            }else{
                for(;;){
                    dest[ox]=a86_placebo_dw3_quant(a86_placebo_dw3_dot(a,b,c),mult,bias,l->leaky);
                    if(++ox==last)break;
                    r0+=2;r1+=2;r2+=2;
                    a=(a>>16)|(uint32_t)(uint8_t)r0[1]<<8|(uint32_t)(uint8_t)r0[2]<<16;
                    b=(b>>16)|(uint32_t)(uint8_t)r1[1]<<8|(uint32_t)(uint8_t)r1[2]<<16;
                    c=(c>>16)|(uint32_t)(uint8_t)r2[1]<<8|(uint32_t)(uint8_t)r2[2]<<16;
                }
            }
            for(;ox<l->ow;++ox)
                dest[ox]=a86_placebo_dw3_quant(ai_dot3x3_loaded(channel,l->ih,l->iw,y,(int32_t)(ox*s)-(int32_t)l->pad),mult,bias,l->leaky);
        }
    }
    return AI_BLOCK_OK;
}
#endif
