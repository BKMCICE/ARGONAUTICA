/* Nine-lane signed INT8 MMIO dot product and CHW convolution packing. */
#ifndef AI_MAC_H
#define AI_MAC_H

#include "soc.h"

static inline int32_t ai_dot9_packed(uint32_t p0, uint32_t p1, uint32_t p2,
                                     uint32_t w0, uint32_t w1, uint32_t w2)
{
#ifdef YOLO_HOST_TEST
    extern uint32_t host_ai_calls;
    const uint32_t pixels[3] = {p0, p1, p2};
    const uint32_t weights[3] = {w0, w1, w2};
    int32_t sum = 0;
    ++host_ai_calls;
    for (uint32_t lane = 0; lane < 9; ++lane) {
        uint32_t shift = (lane & 3u) * 8u;
        int8_t pixel = (int8_t)(pixels[lane >> 2] >> shift);
        int8_t weight = (int8_t)(weights[lane >> 2] >> shift);
        sum += (int32_t)pixel * (int32_t)weight;
    }
    return sum;
#else
    AI_PIX0 = p0; AI_PIX1 = p1; AI_PIX2 = p2;
    AI_WGT0 = w0; AI_WGT1 = w1; AI_WGT2 = w2;
    AI_CTRL = AI_START;
    while (!(AI_CTRL & AI_DONE)) { }
    return (int32_t)AI_ACCUM;
#endif
}

static inline int32_t ai_dot3x3(const int8_t *input, const int8_t *kernel,
                                uint32_t height, uint32_t width,
                                int32_t top, int32_t left)
{
    uint32_t pixels[3] = {0, 0, 0};
    uint32_t weights[3] = {0, 0, 0};
    for (uint32_t ky = 0; ky < 3; ++ky) {
        int32_t y = top + (int32_t)ky;
        for (uint32_t kx = 0; kx < 3; ++kx) {
            int32_t x = left + (int32_t)kx;
            uint32_t lane = ky * 3 + kx;
            if (y >= 0 && y < (int32_t)height && x >= 0 && x < (int32_t)width)
                pixels[lane >> 2] |= (uint32_t)(uint8_t)input[y * width + x] <<
                                      ((lane & 3u) * 8u);
            weights[lane >> 2] |= (uint32_t)(uint8_t)kernel[lane] <<
                                   ((lane & 3u) * 8u);
        }
    }
    return ai_dot9_packed(pixels[0], pixels[1], pixels[2],
                          weights[0], weights[1], weights[2]);
}

static inline int32_t ai_dot1x1(const int8_t *input, const int8_t *kernel,
                                uint32_t plane_size, uint32_t pixel, uint32_t channels)
{
    uint32_t pixels[3] = {0, 0, 0};
    uint32_t weights[3] = {0, 0, 0};
    for (uint32_t lane = 0; lane < channels; ++lane) {
        pixels[lane >> 2] |= (uint32_t)(uint8_t)input[lane * plane_size + pixel] <<
                              ((lane & 3u) * 8u);
        weights[lane >> 2] |= (uint32_t)(uint8_t)kernel[lane] <<
                               ((lane & 3u) * 8u);
    }
    return ai_dot9_packed(pixels[0], pixels[1], pixels[2],
                          weights[0], weights[1], weights[2]);
}

static inline int32_t ai_dot5x5(const int8_t *input, const int8_t *kernel,
                                uint32_t height, uint32_t width,
                                int32_t top, int32_t left)
{
    int32_t total = 0;
    for (uint32_t block = 0; block < 25; block += 9) {
        uint32_t pixels[3] = {0, 0, 0};
        uint32_t weights[3] = {0, 0, 0};
        for (uint32_t lane = 0; lane < 9 && block + lane < 25; ++lane) {
            uint32_t pos = block + lane;
            int32_t y = top + (int32_t)(pos / 5);
            int32_t x = left + (int32_t)(pos % 5);
            if (y >= 0 && y < (int32_t)height && x >= 0 && x < (int32_t)width)
                pixels[lane >> 2] |= (uint32_t)(uint8_t)input[y * width + x] <<
                                      ((lane & 3u) * 8u);
            weights[lane >> 2] |= (uint32_t)(uint8_t)kernel[pos] <<
                                   ((lane & 3u) * 8u);
        }
        total += ai_dot9_packed(pixels[0], pixels[1], pixels[2],
                                weights[0], weights[1], weights[2]);
    }
    return total;
}

#endif
