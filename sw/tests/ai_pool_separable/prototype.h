/* Isolated fixed-graph experiment; no production dispatch includes this file.
 * Nonoverlapping input/output/scratch and stable layer are caller contracts.
 * Scratch is one 10x10 channel, reused sequentially, not a whole tensor.
 * Original -127 initial best is retained, including raw INT8_MIN inputs.
 * Requantize only after the vertical pass, never between passes. */
#ifndef A93_POOL_SEPARABLE_H
#define A93_POOL_SEPARABLE_H
static int a93_pool(const YoloLayer *l,const int8_t *input,int8_t *output,
                    int8_t *scratch,uint32_t capacity){
    if(!l||!input||!output||!scratch||capacity<100u||
       l->kind!=YOLO_MAXPOOL||l->ih!=10||l->iw!=10||l->ic!=48||
       l->oh!=10||l->ow!=10||l->oc!=48||l->stride!=1||
       (l->size!=3&&l->size!=5&&l->size!=9)||l->pad!=l->size/2u||
       l->prev_q24!=29567173)return -2;
    for(uint32_t c=0;c<48;++c){
        const int8_t *src=input+c*100u;int8_t *dst=output+c*100u;
        for(uint32_t y=0;y<10;++y)for(uint32_t x=0;x<10;++x){
            int32_t best=-127;
            int32_t first=(int32_t)x-(int32_t)l->pad;
            int32_t end=first+(int32_t)l->size;
            if(first<0)first=0;
            if(end>10)end=10;
            for(int32_t ix=first;ix<end;++ix){int32_t v=src[y*10u+(uint32_t)ix];if(v>best)best=v;}
            scratch[y*10u+x]=(int8_t)best;
        }
        for(uint32_t y=0;y<10;++y)for(uint32_t x=0;x<10;++x){
            int32_t best=-127;
            int32_t first=(int32_t)y-(int32_t)l->pad;
            int32_t end=first+(int32_t)l->size;
            if(first<0)first=0;
            if(end>10)end=10;
            for(int32_t iy=first;iy<end;++iy){int32_t v=scratch[(uint32_t)iy*10u+x];if(v>best)best=v;}
            dst[y*10u+x]=clip8(apply_q24(best,l->prev_q24));
        }
    }
    return 0;
}
#endif
