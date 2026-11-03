#include "soc.h"
#include "ai_mac_prepack.h"

static int8_t pixels[224 * 17], weights[224];
static uint32_t packed[25 * 3];
static const uint32_t widths[] = {1,8,9,10,16,17,18,19,24,31,32,48,96,120,136,192,223,224};

int main(void)
{
    AI_BIAS = 0;
    uint32_t cases = 0;
    for (uint32_t test = 0; test < sizeof(widths)/sizeof(widths[0]); ++test) {
        uint32_t channels = widths[test];
        uint32_t blocks = (channels + 8) / 9;
        for (uint32_t kernel = 0; kernel < 3; ++kernel) {
            for (uint32_t i = 0; i < sizeof(pixels); ++i)
                pixels[i] = (int8_t)((i * 43u + kernel * 71u + test) & 255u);
            for (uint32_t i = 0; i < sizeof(weights); ++i)
                weights[i] = (int8_t)((i * 89u + kernel * 127u + test) & 255u);
            for (uint32_t block = 0; block < blocks; ++block) {
                uint32_t first = block * 9, count = channels - first;
                if (count > 9) count = 9;
                packed[block*3] = packed[block*3+1] = packed[block*3+2] = 0xffffffffu;
                ai_pack_1x1_weights(weights + first, count, packed + block*3);
                if (packed[block*3+2] & 0xffffff00u) return 1;
                for (uint32_t lane = count; lane < 9; ++lane)
                    if ((packed[block*3+(lane>>2)] >> ((lane&3u)*8)) & 255u) return 2;
            }
            for (uint32_t pixel = 0; pixel < 17; pixel += 2) {
                int64_t actual = 0, expected = 0;
                for (uint32_t lane = 0; lane < channels; ++lane)
                    expected += (int32_t)pixels[lane*17+pixel] * weights[lane];
                for (uint32_t block = 0; block < blocks; ++block) {
                    uint32_t first = block * 9, count = channels - first;
                    if (count > 9) count = 9;
                    actual += ai_dot1x1_prepacked(pixels + first*17, 17, pixel, count, packed + block*3);
                }
                if (actual != expected) {
                    uart_puts("AI_WEIGHT_PREPACK_FAIL channels="); uart_putdec(channels);
                    uart_puts(" pixel="); uart_putdec(pixel); uart_putc('\n');
                    return 3;
                }
                ++cases;
            }
        }
    }
    uart_puts("AI_WEIGHT_PREPACK_PASS cases="); uart_putdec(cases); uart_putc('\n');
    return cases == 486 ? 0 : 4;
}
