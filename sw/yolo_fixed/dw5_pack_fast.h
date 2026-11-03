/* A75 production opt-in fixed 9/9/7 layout. Caller has validated disjoint tensors.
 * Border, crop and noncanonical helper arguments retain the original packer.
 * Only byte loads are used; no alignment or speculative out-of-row reads.
 */
#ifndef YOLO_DW5_PACK_FAST_H
#define YOLO_DW5_PACK_FAST_H
static inline uint32_t dw5_fast_byte(const int8_t *p) { return (uint32_t)(uint8_t)*p; }
static inline uint32_t dw5_fast_word4(const int8_t *p) {
    return dw5_fast_byte(p)|(dw5_fast_byte(p+1)<<8)|(dw5_fast_byte(p+2)<<16)|(dw5_fast_byte(p+3)<<24);
}
static inline void dw5_pack_fast(const int8_t *src,uint32_t h,uint32_t w,int32_t y,int32_t x,
                            uint32_t first,uint32_t count,uint32_t p[3]) {
    if(h>=5&&w>=5&&y>=0&&x>=0&&(uint32_t)y<=h-5&&(uint32_t)x<=w-5) {
        const int8_t *r=src+(uint32_t)y*w+(uint32_t)x;
        if(first==0&&count==9) {
            p[0]=dw5_fast_word4(r);
            p[1]=dw5_fast_byte(r+4)|(dw5_fast_byte(r+w)<<8)|(dw5_fast_byte(r+w+1)<<16)|(dw5_fast_byte(r+w+2)<<24);
            p[2]=dw5_fast_byte(r+w+3);return;
        }
        if(first==9&&count==9) {
            r+=w;
            p[0]=dw5_fast_byte(r+4)|(dw5_fast_byte(r+w)<<8)|(dw5_fast_byte(r+w+1)<<16)|(dw5_fast_byte(r+w+2)<<24);
            p[1]=dw5_fast_byte(r+w+3)|(dw5_fast_byte(r+w+4)<<8)|(dw5_fast_byte(r+2*w)<<16)|(dw5_fast_byte(r+2*w+1)<<24);
            p[2]=dw5_fast_byte(r+2*w+2);return;
        }
        if(first==18&&count==7) {
            r+=3*w;
            p[0]=dw5_fast_byte(r+3)|(dw5_fast_byte(r+4)<<8)|(dw5_fast_byte(r+w)<<16)|(dw5_fast_byte(r+w+1)<<24);
            p[1]=dw5_fast_byte(r+w+2)|(dw5_fast_byte(r+w+3)<<8)|(dw5_fast_byte(r+w+4)<<16);
            p[2]=0;return;
        }
    }
    dw5_pack5(src,h,w,y,x,first,count,p);
}
#endif
