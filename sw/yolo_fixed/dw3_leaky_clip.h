/* Fixed-model leaky Q24 followed by clip, exact for every int32 activation.
 * Q(1264)=126; Q(1265)=127 and Q is monotone. Saturate before negating
 * INT_MIN. In the remaining interval product+half is at most 2129029216.
 * The preceding accumulator Q24 and bias retain their original contract. */
#ifndef YOLO_DW3_LEAKY_CLIP_H
#define YOLO_DW3_LEAKY_CLIP_H
#if !defined(YOLO_LEAKY_Q24) || YOLO_LEAKY_Q24 != 1677722
#error "DW3 leaky specialization requires fixed multiplier 1677722"
#endif
static inline int8_t dw3_leaky_clip(int32_t v,uint32_t leaky){
    if(leaky&&v<0){
        if(v<=-1265)return -127;
        uint32_t product=(uint32_t)(-v)*1677722u;
        return (int8_t)-(int32_t)((product+8388608u)>>24);
    }
    return clip8(v);
}
#endif
