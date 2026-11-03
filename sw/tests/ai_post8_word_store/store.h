/* Only four valid, aligned little-endian bytes use a word store. Builtin
 * memcpy preserves character-array alias semantics; no uint32_t lvalue cast.
 * Unaligned/tail destinations retain byte stores and never touch tail bytes. */
#ifndef A79_STORE_H
#define A79_STORE_H
static inline void a79_store(int8_t *dest,uint32_t word,uint32_t count){
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    if(count==4u&&((uintptr_t)dest&3u)==0){
        __builtin_memcpy(__builtin_assume_aligned(dest,4),&word,4);return;
    }
#endif
    for(uint32_t byte=0;byte<count;++byte){dest[byte]=(int8_t)word;word>>=8;}
}
#endif
