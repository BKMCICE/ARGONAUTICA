/* Isolated four-pixel CHW transpose; caller's original cache ownership and
 * validated shape/span/capacity contracts are required. No format/MMIO change. */
#ifndef A82_CACHE_PACK4_H
#define A82_CACHE_PACK4_H
static inline uint32_t a82_load4(const int8_t *p){uint32_t v;__builtin_memcpy(&v,__builtin_assume_aligned(p,4),4);return v;}
static inline void a82_transpose4(uint32_t a,uint32_t b,uint32_t c,uint32_t d,uint32_t *out){
 uint32_t ab0=(a&0x00ff00ffu)|((b&0x00ff00ffu)<<8);
 uint32_t ab1=((a>>8)&0x00ff00ffu)|(b&0xff00ff00u);
 uint32_t cd0=(c&0x00ff00ffu)|((d&0x00ff00ffu)<<8);
 uint32_t cd1=((c>>8)&0x00ff00ffu)|(d&0xff00ff00u);
 out[0]=(ab0&65535u)|(cd0<<16);out[3]=(ab1&65535u)|(cd1<<16);
 out[6]=(ab0>>16)|(cd0&0xffff0000u);out[9]=(ab1>>16)|(cd1&0xffff0000u);
}
#ifdef YOLO_HOST_TEST
static uint32_t a82_fast_pack_calls;
#endif
__attribute__((noinline)) static void a82_cache_pack(const YoloLayer *l,const int8_t *input,
 uint32_t plane,uint32_t out_plane,uint32_t channels,uint32_t blocks){
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
 if(l->stride==1&&l->ih==l->oh&&l->iw==l->ow&&plane==out_plane&&!(plane&3u)&&!((uintptr_t)input&3u)){
#ifdef YOLO_HOST_TEST
  ++a82_fast_pack_calls;
#endif
  for(uint32_t b=0;b<blocks;++b){
   uint32_t count=channels-b*9u;if(count>9)count=9;
   const int8_t *src=input+b*9u*plane;uint32_t *dest=block_input_cache+b*out_plane*3u;
   for(uint32_t p=0;p<out_plane;p+=4,dest+=12){
    uint32_t a=a82_load4(src+p),v=count>1?a82_load4(src+plane+p):0,c=count>2?a82_load4(src+2*plane+p):0,d=count>3?a82_load4(src+3*plane+p):0;
    a82_transpose4(a,v,c,d,dest);
    a=count>4?a82_load4(src+4*plane+p):0;v=count>5?a82_load4(src+5*plane+p):0;c=count>6?a82_load4(src+6*plane+p):0;d=count>7?a82_load4(src+7*plane+p):0;
    a82_transpose4(a,v,c,d,dest+1);
    a=count>8?a82_load4(src+8*plane+p):0;
    dest[2]=a&255u;dest[5]=(a>>8)&255u;dest[8]=(a>>16)&255u;dest[11]=a>>24;
   }
  }
#ifdef YOLO_HOST_TEST
  ++host_block_cached_groups;host_block_cached_pixels+=out_plane;
#endif
  return;
 }
#endif
 block_cache_pack(l,input,plane,out_plane,channels,blocks);
}
#endif
