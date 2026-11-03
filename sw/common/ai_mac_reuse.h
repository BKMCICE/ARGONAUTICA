/* Resident weights for sequential nine-lane MMIO dot products.
 * The caller owns the AI unit until the last pixel and reloads on each kernel.
 * channels is 1..9; both helpers zero unused lanes before each submission.
 */
#ifndef AI_MAC_REUSE_H
#define AI_MAC_REUSE_H
#include "ai_mac.h"

#ifndef YOLO_1X1_SMALL_PACK
#define YOLO_1X1_SMALL_PACK 0
#endif
#if YOLO_1X1_SMALL_PACK != 0 && YOLO_1X1_SMALL_PACK != 1
#error "YOLO_1X1_SMALL_PACK supports only 0 or 1"
#endif
#if YOLO_1X1_SMALL_PACK && !YOLO_REUSE_1X1_WEIGHTS
#error "YOLO_1X1_SMALL_PACK requires YOLO_REUSE_1X1_WEIGHTS=1"
#endif

#ifdef YOLO_HOST_TEST
static uint32_t host_resident_weights[3];
#endif

static inline void ai_load_1x1_weights(const int8_t *kernel, uint32_t channels)
{
    uint32_t packed[3] = {0, 0, 0};
    for (uint32_t lane = 0; lane < channels; ++lane)
        packed[lane >> 2] |= (uint32_t)(uint8_t)kernel[lane] << ((lane & 3u) * 8u);
#ifdef YOLO_HOST_TEST
    host_resident_weights[0] = packed[0];
    host_resident_weights[1] = packed[1];
    host_resident_weights[2] = packed[2];
#else
    AI_WGT0 = packed[0]; AI_WGT1 = packed[1]; AI_WGT2 = packed[2];
#endif
}

static inline int32_t ai_dot1x1_loaded(const int8_t *input, uint32_t plane_size,
                                      uint32_t pixel, uint32_t channels)
{
    uint32_t packed[3] = {0, 0, 0};
#if YOLO_1X1_SMALL_PACK
    if (channels == 4u || channels == 8u) {
        /* CHW channels are plane_size bytes apart; only byte loads are valid.
         * Keep unused PIX words zero, including transitions from nine lanes. */
        const int8_t *p = input + pixel;
        packed[0] = (uint32_t)(uint8_t)p[0] |
                    (uint32_t)(uint8_t)p[plane_size] << 8 |
                    (uint32_t)(uint8_t)p[2u * plane_size] << 16 |
                    (uint32_t)(uint8_t)p[3u * plane_size] << 24;
        if (channels == 8u)
            packed[1] = (uint32_t)(uint8_t)p[4u * plane_size] |
                        (uint32_t)(uint8_t)p[5u * plane_size] << 8 |
                        (uint32_t)(uint8_t)p[6u * plane_size] << 16 |
                        (uint32_t)(uint8_t)p[7u * plane_size] << 24;
    } else
#endif
    {
    for (uint32_t lane = 0; lane < channels; ++lane)
        packed[lane >> 2] |= (uint32_t)(uint8_t)input[lane * plane_size + pixel] <<
                              ((lane & 3u) * 8u);
    }
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
