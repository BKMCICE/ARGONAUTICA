/* Exact composition of leaky Q24 and final clip for any int32 v.
 * Q(1264)=126, Q(1265)=127 and Q is monotone for positive magnitude.
 * Saturate before negation, including INT_MIN. Small product+half <2^31. */
#ifndef A91_LEAKY_CLIP_H
#define A91_LEAKY_CLIP_H
#if !defined(YOLO_LEAKY_Q24) || YOLO_LEAKY_Q24 != 1677722
#error "A91 specialization requires the fixed leaky Q24 multiplier1677722"
#endif
static inline int8_t a91_leaky_clip(int32_t v,uint32_t leaky){
    if(leaky&&v<0){
        if(v<=-1265)return -127;
        uint32_t product=(uint32_t)(-v)*1677722u;
        return (int8_t)-(int32_t)((product+8388608u)>>24);
    }
    return clip8(v);
}
#endif
