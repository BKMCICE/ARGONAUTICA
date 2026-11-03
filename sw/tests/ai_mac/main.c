#include "soc.h"
#include "ai_mac.h"

static int run(uint32_t control, int expected, int expected_raw)
{
    AI_CTRL = control;
    for (unsigned timeout = 0; timeout < 1000; timeout++) {
        if (AI_CTRL & AI_DONE) {
            int actual = (int)AI_RESULT;
            int raw = (int)AI_ACCUM;
            AI_CTRL = AI_CLEAR_DONE;
            return actual == expected && raw == expected_raw && !(AI_CTRL & AI_DONE);
        }
    }
    return 0;
}

int main(void)
{
    AI_PIX0 = 0x04030201u; AI_PIX1 = 0x08070605u; AI_PIX2 = 9;
    AI_WGT0 = 0x01010101u; AI_WGT1 = 0x01010101u; AI_WGT2 = 1;
    AI_BIAS = (uint32_t)-5;
    if (!run(AI_START | (1u << 8), 20, 40)) return 1;
    AI_PIX0 = 0xFFFFFFFFu; AI_PIX1 = 0xFFFFFFFFu; AI_PIX2 = 0xFF;
    AI_BIAS = 0;
    if (!run(AI_START, -9, -9)) return 2;
    if (!run(AI_START | AI_RELU, 0, -9)) return 3;
    AI_PIX0 = 0x7F7F7F7Fu; AI_PIX1 = 0x7F7F7F7Fu; AI_PIX2 = 127;
    AI_WGT0 = 0x7F7F7F7Fu; AI_WGT1 = 0x7F7F7F7Fu; AI_WGT2 = 127;
    if (!run(AI_START, 127, 145161)) return 4;
    static const int8_t image[16] = {
        -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
    };
    static const int8_t kernel[9] = {-1, 2, -3, 4, -5, 6, -7, 8, -9};
    AI_BIAS = 0;
    if (ai_dot3x3(image, kernel, 4, 4, 0, 0) != -36) return 5;
    if (ai_dot3x3(image, kernel, 4, 4, -1, -1) != -7) return 6;
    if (ai_dot3x3(image, kernel, 4, 4, 1, 1) != -61) return 7;
    static const int8_t point_image[40] = {
        -5,-4,-3,-2, -1,0,1,2, 3,4,5,6, 7,8,9,10, 11,12,13,14,
        15,16,17,18, 19,20,21,22, 23,24,25,26, 27,28,29,30, 31,32,33,34
    };
    static const int8_t point_kernel[10] = {-5,-4,-3,-2,-1,0,1,2,3,4};
    if (ai_dot1x1(point_image, point_kernel, 4, 2, 9) +
        ai_dot1x1(point_image + 36, point_kernel + 9, 4, 2, 1) != 255) return 8;
    static const int8_t large_image[25] = {
        -12,-11,-10,-9,-8, -7,-6,-5,-4,-3, -2,-1,0,1,2,
        3,4,5,6,7, 8,9,10,11,12
    };
    static const int8_t large_kernel[25] = {
        -3,-2,-1,0,1,2,3, -3,-2,-1,0,1,2,3,
        -3,-2,-1,0,1,2,3, -3,-2,-1,0
    };
    if (ai_dot5x5(large_image, large_kernel, 5, 5, -1, -1) != -14) return 9;
    if (ai_dot5x5(large_image, large_kernel, 5, 5, 0, 0) != 26) return 10;
    return 0;
}
