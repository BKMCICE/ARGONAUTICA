__attribute__((noinline)) static int a88_placebo_block(const YoloLayer *l,const int8_t *input,
    int8_t *output,const int8_t *weights,const int32_t *params){
    if(!l||l->kind!=YOLO_CONV||l->size!=5||!l->ic||l->ic!=l->oc||l->groups!=l->ic||
       !l->stride||l->stride>INT32_MAX||l->pad>4||!l->ih||!l->iw||!l->oh||!l->ow||
       l->ih>INT32_MAX-8u||l->iw>INT32_MAX-8u||l->ih+2*l->pad<5||l->iw+2*l->pad<5||
       l->oh-1u>(l->ih+2*l->pad-5u)/l->stride||l->ow-1u>(l->iw+2*l->pad-5u)/l->stride||
       l->iw>UINT32_MAX/l->ih||l->ow>UINT32_MAX/l->oh)return AI_BLOCK_BAD_SHAPE;
    uint32_t plane=l->ih*l->iw,op=l->oh*l->ow;
    if(l->ic>UINT32_MAX/plane||l->oc>UINT32_MAX/op||l->oc>UINT32_MAX/25u)return AI_BLOCK_BAD_SHAPE;
    uint32_t ni=l->ic*plane,no=l->oc*op,nw=l->oc*25,np=l->oc*8;
    if(!dw5_span(input,ni)||!dw5_span(output,no)||!dw5_span(weights,nw)||!dw5_span(params,np)||
       !dw5_disjoint(output,no,input,ni)||!dw5_disjoint(output,no,weights,nw)||
       !dw5_disjoint(output,no,params,np))return AI_BLOCK_BAD_SHAPE;
    if(AI_BLOCK_READ(AI_BLOCK_REG_ID)!=AI_BLOCK_ID)return AI_BLOCK_UNSUPPORTED;
#if YOLO_DW5_POST8
    /* Select before writes. A331 alone is not a postprocessing capability.
     * Validation, packing and submission are shared by new and old hardware. */
    uint32_t post_id=AI_BLOCK_READ(0x2cu),raw_id=AI_BLOCK_READ(0x28u);
    if((post_id&&post_id!=0x41343831u)||(raw_id&&raw_id!=0x41333331u)||
       (post_id&&raw_id!=0x41333331u))return AI_BLOCK_HW_ERROR;
    uint32_t use_post=post_id!=0;
#endif
    if(AI_BLOCK_READ(AI_BLOCK_CTRL)&1u)return AI_BLOCK_HW_ERROR;
#if YOLO_DW5_POST8
    if(use_post)AI_BLOCK_WRITE(0x204u,1u|(l->leaky?2u:0u));
#endif
    uint32_t p[3];
#if !YOLO_DW5_POST8
    int32_t acc[8];
#endif
    for(uint32_t oc=0;oc<l->oc;++oc){
        AI_BLOCK_WRITE(AI_BLOCK_CTRL,4u);AI_BLOCK_WRITE(AI_BLOCK_WADDR,0);
#if YOLO_DW5_POST8
        if(use_post){
            AI_BLOCK_WRITE(0x208u,0u);
            AI_BLOCK_WRITE(0x20cu,(uint32_t)params[oc*2]);
            AI_BLOCK_WRITE(0x210u,(uint32_t)params[oc*2+1]);
        }
#endif
        for(uint32_t b=0;b<3;++b){
            ai_pack_1x1_weights(weights+oc*25+b*9,b==2?7:9,p);
            for(uint32_t k=0;k<3;++k)AI_BLOCK_WRITE(AI_BLOCK_WDATA,p[k]);
        }
        const int8_t *channel=input+oc*plane;
        for(uint32_t oy=0;oy<l->oh;++oy)for(uint32_t ox=0;ox<l->ow;){
            uint32_t pixels=l->ow-ox;if(pixels>8)pixels=8;
            AI_BLOCK_WRITE(AI_BLOCK_CTRL,4u);AI_BLOCK_WRITE(AI_BLOCK_PADDR,0);
            for(uint32_t b=0;b<3;++b)for(uint32_t px=0;px<pixels;++px){
                DW5_PACK_INPUT(channel,l->ih,l->iw,(int32_t)(oy*l->stride)-(int32_t)l->pad,
                    (int32_t)((ox+px)*l->stride)-(int32_t)l->pad,b*9,b==2?7:9,p);
                for(uint32_t k=0;k<3;++k)AI_BLOCK_WRITE(AI_BLOCK_PDATA,p[k]);
            }
            AI_BLOCK_WRITE(AI_BLOCK_SHAPE,pixels|(1u<<4)|(3u<<8)|(7u<<16));AI_BLOCK_WRITE(AI_BLOCK_CTRL,1u);
            uint32_t status=0,polls=0;
            do{status=AI_BLOCK_READ(AI_BLOCK_CTRL);++polls;}while(!(status&2u)&&polls<100000u);
            if(!(status&2u))return AI_BLOCK_TIMEOUT;
            if(status&5u)return AI_BLOCK_HW_ERROR;
#if YOLO_DW5_POST8
            if(use_post){
                AI_BLOCK_WRITE(0x21cu,0u);
                for(uint32_t px=0;px<pixels;){
                    uint32_t word=AI_BLOCK_READ(0x220u),count=pixels-px;
                    if(count>4)count=4;
                    for(uint32_t byte=0;byte<count;++byte){
                        output[oc*op+oy*l->ow+ox+px++]=(int8_t)word;word>>=8;
                    }
                }
                if(AI_BLOCK_READ(AI_BLOCK_CTRL)&4u)return AI_BLOCK_HW_ERROR;
            }else{
                int rc=block_post8_raw_store(output+oc*op+oy*l->ow+ox,
                    op,params+oc*2,pixels,1u,l->leaky);
                if(rc)return rc;
            }
#else
            AI_BLOCK_WRITE(AI_BLOCK_RADDR,0);
            for(uint32_t px=0;px<pixels;++px)acc[px]=(int32_t)AI_BLOCK_READ(AI_BLOCK_RDATA);
            if(AI_BLOCK_READ(AI_BLOCK_CTRL)&4u)return AI_BLOCK_HW_ERROR;
            for(uint32_t px=0;px<pixels;++px){
                int32_t v=apply_q24(acc[px],params[oc*2])+params[oc*2+1];
                if(l->leaky&&v<0)v=apply_q24(v,YOLO_LEAKY_Q24);
                output[oc*op+oy*l->ow+ox+px]=clip8(v);
            }
#endif
            ox+=pixels;
        }
    }
#if YOLO_DW5_POST8
    if(use_post)AI_BLOCK_WRITE(0x204u,0u);
#endif
    return AI_BLOCK_OK;
}

__attribute__((noinline)) static int a88_candidate_block(const YoloLayer *l,const int8_t *input,
    int8_t *output,const int8_t *weights,const int32_t *params){
    if(!l||l->kind!=YOLO_CONV||l->size!=5||!l->ic||l->ic!=l->oc||l->groups!=l->ic||
       !l->stride||l->stride>INT32_MAX||l->pad>4||!l->ih||!l->iw||!l->oh||!l->ow||
       l->ih>INT32_MAX-8u||l->iw>INT32_MAX-8u||l->ih+2*l->pad<5||l->iw+2*l->pad<5||
       l->oh-1u>(l->ih+2*l->pad-5u)/l->stride||l->ow-1u>(l->iw+2*l->pad-5u)/l->stride||
       l->iw>UINT32_MAX/l->ih||l->ow>UINT32_MAX/l->oh)return AI_BLOCK_BAD_SHAPE;
    uint32_t plane=l->ih*l->iw,op=l->oh*l->ow;
    if(l->ic>UINT32_MAX/plane||l->oc>UINT32_MAX/op||l->oc>UINT32_MAX/25u)return AI_BLOCK_BAD_SHAPE;
    uint32_t ni=l->ic*plane,no=l->oc*op,nw=l->oc*25,np=l->oc*8;
    if(!dw5_span(input,ni)||!dw5_span(output,no)||!dw5_span(weights,nw)||!dw5_span(params,np)||
       !dw5_disjoint(output,no,input,ni)||!dw5_disjoint(output,no,weights,nw)||
       !dw5_disjoint(output,no,params,np))return AI_BLOCK_BAD_SHAPE;
    if(AI_BLOCK_READ(AI_BLOCK_REG_ID)!=AI_BLOCK_ID)return AI_BLOCK_UNSUPPORTED;
#if YOLO_DW5_POST8
    /* Select before writes. A331 alone is not a postprocessing capability.
     * Validation, packing and submission are shared by new and old hardware. */
    uint32_t post_id=AI_BLOCK_READ(0x2cu),raw_id=AI_BLOCK_READ(0x28u);
    if((post_id&&post_id!=0x41343831u)||(raw_id&&raw_id!=0x41333331u)||
       (post_id&&raw_id!=0x41333331u))return AI_BLOCK_HW_ERROR;
    uint32_t use_post=post_id!=0;
#endif
    if(AI_BLOCK_READ(AI_BLOCK_CTRL)&1u)return AI_BLOCK_HW_ERROR;
#if YOLO_DW5_POST8
    if(use_post)AI_BLOCK_WRITE(0x204u,1u|(l->leaky?2u:0u));
#endif
    uint32_t p[3];
#if !YOLO_DW5_POST8
    int32_t acc[8];
#endif
    for(uint32_t oc=0;oc<l->oc;++oc){
        AI_BLOCK_WRITE(AI_BLOCK_CTRL,4u);AI_BLOCK_WRITE(AI_BLOCK_WADDR,0);
#if YOLO_DW5_POST8
        if(use_post){
            AI_BLOCK_WRITE(0x208u,0u);
            AI_BLOCK_WRITE(0x20cu,(uint32_t)params[oc*2]);
            AI_BLOCK_WRITE(0x210u,(uint32_t)params[oc*2+1]);
        }
#endif
        for(uint32_t b=0;b<3;++b){
            ai_pack_1x1_weights(weights+oc*25+b*9,b==2?7:9,p);
            for(uint32_t k=0;k<3;++k)AI_BLOCK_WRITE(AI_BLOCK_WDATA,p[k]);
        }
        const int8_t *channel=input+oc*plane;
        for(uint32_t oy=0;oy<l->oh;++oy)for(uint32_t ox=0;ox<l->ow;){
            uint32_t pixels=l->ow-ox;if(pixels>8)pixels=8;
            AI_BLOCK_WRITE(AI_BLOCK_CTRL,4u);AI_BLOCK_WRITE(AI_BLOCK_PADDR,0);
            for(uint32_t b=0;b<3;++b)for(uint32_t px=0;px<pixels;++px){
                DW5_PACK_INPUT(channel,l->ih,l->iw,(int32_t)(oy*l->stride)-(int32_t)l->pad,
                    (int32_t)((ox+px)*l->stride)-(int32_t)l->pad,b*9,b==2?7:9,p);
                for(uint32_t k=0;k<3;++k)AI_BLOCK_WRITE(AI_BLOCK_PDATA,p[k]);
            }
            AI_BLOCK_WRITE(AI_BLOCK_SHAPE,pixels|(1u<<4)|(3u<<8)|(7u<<16));AI_BLOCK_WRITE(AI_BLOCK_CTRL,1u);
            uint32_t status=0,polls=0;
            do{status=AI_BLOCK_READ(AI_BLOCK_CTRL);++polls;}while(!(status&2u)&&polls<100000u);
            if(!(status&2u))return AI_BLOCK_TIMEOUT;
            if(status&5u)return AI_BLOCK_HW_ERROR;
#if YOLO_DW5_POST8
            if(use_post){
                AI_BLOCK_WRITE(0x21cu,0u);
                for(uint32_t px=0;px<pixels;){
                    uint32_t word=AI_BLOCK_READ(0x220u),count=pixels-px;
                    if(count>4)count=4;
                    post8_word_store(output+oc*op+oy*l->ow+ox+px,word,count);
                    px+=count;
                }
                if(AI_BLOCK_READ(AI_BLOCK_CTRL)&4u)return AI_BLOCK_HW_ERROR;
            }else{
                int rc=block_post8_raw_store(output+oc*op+oy*l->ow+ox,
                    op,params+oc*2,pixels,1u,l->leaky);
                if(rc)return rc;
            }
#else
            AI_BLOCK_WRITE(AI_BLOCK_RADDR,0);
            for(uint32_t px=0;px<pixels;++px)acc[px]=(int32_t)AI_BLOCK_READ(AI_BLOCK_RDATA);
            if(AI_BLOCK_READ(AI_BLOCK_CTRL)&4u)return AI_BLOCK_HW_ERROR;
            for(uint32_t px=0;px<pixels;++px){
                int32_t v=apply_q24(acc[px],params[oc*2])+params[oc*2+1];
                if(l->leaky&&v<0)v=apply_q24(v,YOLO_LEAKY_Q24);
                output[oc*op+oy*l->ow+ox+px]=clip8(v);
            }
#endif
            ox+=pixels;
        }
    }
#if YOLO_DW5_POST8
    if(use_post)AI_BLOCK_WRITE(0x204u,0u);
#endif
    return AI_BLOCK_OK;
}
