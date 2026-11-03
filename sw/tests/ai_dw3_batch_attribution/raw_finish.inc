__attribute__((noinline)) static int a90_raw_finish(int8_t *dest,uint32_t count,const int32_t *params,uint32_t leaky){
    AI_BLOCK_WRITE(AI_BLOCK_SHAPE,count|(1u<<4)|(1u<<8)|(9u<<16));
    AI_BLOCK_WRITE(AI_BLOCK_CTRL,1u);
    uint32_t status=0,polls=0;
    do{status=AI_BLOCK_READ(AI_BLOCK_CTRL);++polls;}while(!(status&2u)&&polls<100000u);
    if(!(status&2u))return AI_BLOCK_TIMEOUT;
    if(status&5u)return AI_BLOCK_HW_ERROR;
    int32_t acc[8];AI_BLOCK_WRITE(AI_BLOCK_RADDR,0u);
    for(uint32_t px=0;px<count;++px)acc[px]=(int32_t)AI_BLOCK_READ(AI_BLOCK_RDATA);
    if(AI_BLOCK_READ(AI_BLOCK_CTRL)&4u)return AI_BLOCK_HW_ERROR;
    int32_t mult=params[0],bias=params[1];
    for(uint32_t px=0;px<count;++px)dest[px]=dw3_quant(acc[px],mult,bias,leaky);
    return AI_BLOCK_OK;
}
