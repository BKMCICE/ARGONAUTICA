/* A74 isolated fixed 9/9/7 layout. Caller has validated disjoint tensors.
 * Border, crop and noncanonical helper arguments retain the original packer.
 * Only byte loads are used; no alignment or speculative out-of-row reads.
 */
#ifndef A74_FAST_PACK_H
#define A74_FAST_PACK_H
static inline uint32_t a74_byte(const int8_t *p) { return (uint32_t)(uint8_t)*p; }
static inline uint32_t a74_word4(const int8_t *p) {
    return a74_byte(p)|(a74_byte(p+1)<<8)|(a74_byte(p+2)<<16)|(a74_byte(p+3)<<24);
}
static inline void a74_pack5(const int8_t *src,uint32_t h,uint32_t w,int32_t y,int32_t x,
                            uint32_t first,uint32_t count,uint32_t p[3]) {
    if(h>=5&&w>=5&&y>=0&&x>=0&&(uint32_t)y<=h-5&&(uint32_t)x<=w-5) {
        const int8_t *r=src+(uint32_t)y*w+(uint32_t)x;
        if(first==0&&count==9) {
            p[0]=a74_word4(r);
            p[1]=a74_byte(r+4)|(a74_byte(r+w)<<8)|(a74_byte(r+w+1)<<16)|(a74_byte(r+w+2)<<24);
            p[2]=a74_byte(r+w+3);return;
        }
        if(first==9&&count==9) {
            r+=w;
            p[0]=a74_byte(r+4)|(a74_byte(r+w)<<8)|(a74_byte(r+w+1)<<16)|(a74_byte(r+w+2)<<24);
            p[1]=a74_byte(r+w+3)|(a74_byte(r+w+4)<<8)|(a74_byte(r+2*w)<<16)|(a74_byte(r+2*w+1)<<24);
            p[2]=a74_byte(r+2*w+2);return;
        }
        if(first==18&&count==7) {
            r+=3*w;
            p[0]=a74_byte(r+3)|(a74_byte(r+4)<<8)|(a74_byte(r+w)<<16)|(a74_byte(r+w+1)<<24);
            p[1]=a74_byte(r+w+2)|(a74_byte(r+w+3)<<8)|(a74_byte(r+w+4)<<16);
            p[2]=0;return;
        }
    }
    dw5_pack5(src,h,w,y,x,first,count,p);
}
#endif
