__attribute__((noinline)) static int a89_placebo_rolling(const YoloLayer *l,const int8_t *input,
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
#ifdef YOLO_HOST_TEST
    ++host_dw3_rolling_calls;
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
                    dest[ox]=dw3_quant(ai_dot3x3_loaded(channel,l->ih,l->iw,y,(int32_t)(ox*s)-(int32_t)l->pad),mult,bias,l->leaky);
                continue;
            }
            uint32_t ox=0;
            for(;ox<first;++ox)
                dest[ox]=dw3_quant(ai_dot3x3_loaded(channel,l->ih,l->iw,y,(int32_t)(ox*s)-(int32_t)l->pad),mult,bias,l->leaky);
            const int8_t *r0=channel+(uint32_t)y*l->iw+ox*s-l->pad,*r1=r0+l->iw,*r2=r1+l->iw;
            uint32_t a=dw3_row(r0),b=dw3_row(r1),c=dw3_row(r2);
            if(s==1){
                for(;;){
                    dest[ox]=dw3_quant(dw3_dot(a,b,c),mult,bias,l->leaky);
                    if(++ox==last)break;
                    ++r0;++r1;++r2;
                    a=(a>>8)|(uint32_t)(uint8_t)r0[2]<<16;
                    b=(b>>8)|(uint32_t)(uint8_t)r1[2]<<16;
                    c=(c>>8)|(uint32_t)(uint8_t)r2[2]<<16;
                }
            }else{
                for(;;){
                    dest[ox]=dw3_quant(dw3_dot(a,b,c),mult,bias,l->leaky);
                    if(++ox==last)break;
                    r0+=2;r1+=2;r2+=2;
                    a=(a>>16)|(uint32_t)(uint8_t)r0[1]<<8|(uint32_t)(uint8_t)r0[2]<<16;
                    b=(b>>16)|(uint32_t)(uint8_t)r1[1]<<8|(uint32_t)(uint8_t)r1[2]<<16;
                    c=(c>>16)|(uint32_t)(uint8_t)r2[1]<<8|(uint32_t)(uint8_t)r2[2]<<16;
                }
            }
            for(;ox<l->ow;++ox)
                dest[ox]=dw3_quant(ai_dot3x3_loaded(channel,l->ih,l->iw,y,(int32_t)(ox*s)-(int32_t)l->pad),mult,bias,l->leaky);
        }
    }
    return AI_BLOCK_OK;
}
