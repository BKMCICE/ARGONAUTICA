#ifndef AI_MAC_INPUT_TILE_H
#define AI_MAC_INPUT_TILE_H
#include "ai_mac_tile.h"

#ifndef YOLO_1X1_PACK9
#define YOLO_1X1_PACK9 0
#endif
#if YOLO_1X1_PACK9 != 0 && YOLO_1X1_PACK9 != 1
#error "YOLO_1X1_PACK9 supports only 0 or 1"
#endif
#if YOLO_1X1_PACK9 && !YOLO_REUSE_1X1_INPUT
#error "YOLO_1X1_PACK9 requires YOLO_REUSE_1X1_INPUT=1"
#endif

/* channels <= 9. With PACK9 enabled, input and packed must not overlap.
 * Production input is in DDR; packed points into the separate TCM scratch. */
static inline void ai_pack_1x1_input(const int8_t *input, uint32_t plane,
    uint32_t pixel, uint32_t channels, uint32_t packed[3])
{
#if YOLO_1X1_PACK9
    if (channels == 9u) {
        const int8_t *p = input + pixel;
        packed[0] = (uint32_t)(uint8_t)p[0] |
                    (uint32_t)(uint8_t)p[plane] << 8 |
                    (uint32_t)(uint8_t)p[2u * plane] << 16 |
                    (uint32_t)(uint8_t)p[3u * plane] << 24;
        packed[1] = (uint32_t)(uint8_t)p[4u * plane] |
                    (uint32_t)(uint8_t)p[5u * plane] << 8 |
                    (uint32_t)(uint8_t)p[6u * plane] << 16 |
                    (uint32_t)(uint8_t)p[7u * plane] << 24;
        packed[2] = (uint32_t)(uint8_t)p[8u * plane];
        return;
    }
#endif
    packed[0] = packed[1] = packed[2] = 0;
    for (uint32_t lane = 0; lane < channels; ++lane)
        packed[lane >> 2] |= (uint32_t)(uint8_t)input[lane * plane + pixel] <<
                             ((lane & 3u) * 8u);
}

static inline int32_t ai_dot_prepacked_loaded(const uint32_t packed[3])
{
#ifdef YOLO_HOST_TEST
    return ai_dot9_packed(packed[0], packed[1], packed[2],
                         host_resident_weights[0], host_resident_weights[1],
                         host_resident_weights[2]);
#else
    AI_PIX0 = packed[0]; AI_PIX1 = packed[1]; AI_PIX2 = packed[2];
    AI_CTRL = AI_START;
    while (!(AI_CTRL & AI_DONE)) { }
    return (int32_t)AI_ACCUM;
#endif
}
#endif
