/* Scalar differential test for the specialized loop, independent of model data. */
#include <stdio.h>
#include <string.h>
#define main yolo_app_main
#include "../../yolo_fixed/main.c"
#undef main

uint32_t host_ai_calls;

static int32_t reference_scale(int64_t value, int32_t multiplier)
{
    int64_t product = value * multiplier;
    int64_t rounded = ((product < 0 ? -product : product) + 8388608) / 16777216;
    return (int32_t)(product < 0 ? -rounded : rounded);
}

int main(void)
{
    int8_t input[224 * 3 * 7 * 9], kernels[6 * 224], actual[6 * 7 * 9 + 8];
    int32_t params[12];
    unsigned cases = 0;
    static const uint32_t widths[] = {10,16,17,18,19,24,31,32,48,96,120,136,192,223,224};
    for (uint32_t groups = 1; groups <= 3; ++groups)
        for (uint32_t width_index = 0; width_index < sizeof(widths)/sizeof(widths[0]); ++width_index)
            for (uint32_t stride = 1; stride <= 2; ++stride)
                for (uint32_t leaky = 0; leaky <= 1; ++leaky) {
                    uint32_t channels = widths[width_index];
                    YoloLayer layer = {0};
                    layer.kind = YOLO_CONV; layer.size = 1;
                    layer.ih = 7; layer.iw = 9; layer.ic = groups * channels;
                    layer.oh = (7 + stride - 1) / stride;
                    layer.ow = (9 + stride - 1) / stride;
                    layer.oc = groups * 2; layer.groups = groups;
                    layer.stride = stride; layer.leaky = leaky;
                    for (unsigned i = 0; i < sizeof(input); ++i)
                        input[i] = (int8_t)((i * 173u + cases * 71u) & 255u);
                    for (unsigned i = 0; i < sizeof(kernels); ++i)
                        kernels[i] = (int8_t)((i * 59u + cases * 127u) & 255u);
                    for (unsigned i = 0; i < 6; ++i) {
                        params[i * 2] = (1 << 18) + (int32_t)i * 3989;
                        params[i * 2 + 1] = (int32_t)i * 37 - 111;
                    }
                    memset(actual, 0x5a, sizeof(actual));
                    conv1x1_prepacked(&layer, input, actual, kernels, params, channels, 2);
                    for (uint32_t oc = 0; oc < layer.oc; ++oc)
                        for (uint32_t y = 0; y < layer.oh; ++y)
                            for (uint32_t x = 0; x < layer.ow; ++x) {
                                int64_t dot = 0;
                                for (uint32_t c = 0; c < channels; ++c)
                                    dot += (int32_t)input[((oc / 2) * channels + c) * 63 +
                                                         y * stride * 9 + x * stride] *
                                           kernels[oc * channels + c];
                                int32_t expected = reference_scale(dot, params[oc * 2]) + params[oc * 2 + 1];
                                if (leaky && expected < 0) expected = reference_scale(expected, 1677722);
                                if (expected > 127) expected = 127;
                                if (expected < -127) expected = -127;
                                if (actual[(oc * layer.oh + y) * layer.ow + x] != expected) {
                                    printf("CONV_PREPACK_FAIL case=%u oc=%u y=%u x=%u\n", cases, oc, y, x);
                                    return 1;
                                }
                            }
                    for (unsigned i = layer.oc * layer.oh * layer.ow; i < sizeof(actual); ++i)
                        if (actual[i] != 0x5a) return 2;
                    ++cases;
                }
    printf("CONV_PREPACK_SCALAR_PASS cases=%u\n", cases);
    return cases == 180 ? 0 : 3;
}
