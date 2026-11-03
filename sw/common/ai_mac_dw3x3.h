/* Depthwise 3x3: the caller loads all nine weights once per channel and owns
 * the AI unit until that channel's last output pixel. No concurrent AI user. */
#ifndef AI_MAC_DW3X3_H
#define AI_MAC_DW3X3_H
#include "ai_mac_reuse.h"

#ifndef YOLO_DW3X3_INTERIOR
#define YOLO_DW3X3_INTERIOR 0
#endif
#if YOLO_DW3X3_INTERIOR != 0 && YOLO_DW3X3_INTERIOR != 1
#error "YOLO_DW3X3_INTERIOR supports only 0 or 1"
#endif

static inline int32_t ai_dot3x3_loaded(const int8_t *input,
                                      uint32_t height, uint32_t width,
                                      int32_t top, int32_t left)
{
    uint32_t pixels[3] = {0, 0, 0};
#if YOLO_DW3X3_INTERIOR
    /* Validate the complete window before forming row pointers. Byte loads
     * preserve alignment independence; the ninth lane has no high bytes. */
    if (height >= 3 && width >= 3 && top >= 0 && left >= 0 &&
        (uint32_t)top <= height - 3 && (uint32_t)left <= width - 3) {
        const int8_t *row0 = input + (uint32_t)top * width + (uint32_t)left;
        const int8_t *row1 = row0 + width;
        const int8_t *row2 = row1 + width;
        pixels[0] = (uint32_t)(uint8_t)row0[0] |
                    (uint32_t)(uint8_t)row0[1] << 8 |
                    (uint32_t)(uint8_t)row0[2] << 16 |
                    (uint32_t)(uint8_t)row1[0] << 24;
        pixels[1] = (uint32_t)(uint8_t)row1[1] |
                    (uint32_t)(uint8_t)row1[2] << 8 |
                    (uint32_t)(uint8_t)row2[0] << 16 |
                    (uint32_t)(uint8_t)row2[1] << 24;
        pixels[2] = (uint32_t)(uint8_t)row2[2];
    } else
#endif
    {
    for (uint32_t ky = 0; ky < 3; ++ky) {
        int32_t y = top + (int32_t)ky;
        for (uint32_t kx = 0; kx < 3; ++kx) {
            int32_t x = left + (int32_t)kx;
            uint32_t lane = ky * 3 + kx;
            if (y >= 0 && y < (int32_t)height && x >= 0 && x < (int32_t)width)
                pixels[lane >> 2] |= (uint32_t)(uint8_t)input[y * width + x] <<
                                      ((lane & 3u) * 8u);
        }
    }
    }
#ifdef YOLO_HOST_TEST
    return ai_dot9_packed(pixels[0], pixels[1], pixels[2],
                          host_resident_weights[0], host_resident_weights[1],
                          host_resident_weights[2]);
#else
    AI_PIX0 = pixels[0]; AI_PIX1 = pixels[1]; AI_PIX2 = pixels[2];
    AI_CTRL = AI_START;
    while (!(AI_CTRL & AI_DONE)) { }
    return (int32_t)AI_ACCUM;
#endif
}
#endif
