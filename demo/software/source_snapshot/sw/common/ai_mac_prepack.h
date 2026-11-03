/* Pack each 1x1 weight block once; input gathering and MMIO stay unchanged. */
#ifndef AI_MAC_PREPACK_H
#define AI_MAC_PREPACK_H
#include "ai_mac.h"

/* channels is 1..9. All unused bytes, including word 2's upper 24 bits, are zero. */
static inline void ai_pack_1x1_weights(const int8_t *kernel, uint32_t channels,
                                      uint32_t packed[3])
{
    packed[0] = 0; packed[1] = 0; packed[2] = 0;
    for (uint32_t lane = 0; lane < channels; ++lane)
        packed[lane >> 2] |= (uint32_t)(uint8_t)kernel[lane] << ((lane & 3u) * 8u);
}

static inline int32_t ai_dot1x1_prepacked(const int8_t *input, uint32_t plane_size,
    uint32_t pixel, uint32_t channels, const uint32_t weights[3])
{
    uint32_t pixels[3] = {0, 0, 0};
    for (uint32_t lane = 0; lane < channels; ++lane)
        pixels[lane >> 2] |= (uint32_t)(uint8_t)input[lane * plane_size + pixel] <<
                              ((lane & 3u) * 8u);
    return ai_dot9_packed(pixels[0], pixels[1], pixels[2],
                          weights[0], weights[1], weights[2]);
}
#endif
