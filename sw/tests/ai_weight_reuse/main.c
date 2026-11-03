#include "soc.h"
#include "ai_mac_reuse.h"

static int8_t pixels[9 * 35];
static int8_t weights[9];

int main(void)
{
    AI_BIAS = 0;
    uint32_t cases = 0;
    /* Descending widths exercise clearing lanes left by the previous kernel. */
    for (uint32_t channels = 9; channels; --channels) {
        for (uint32_t kernel = 0; kernel < 4; ++kernel) {
            for (uint32_t i = 0; i < sizeof(pixels); ++i)
                pixels[i] = (int8_t)((i * 43u + kernel * 71u) & 255u);
            for (uint32_t i = 0; i < 9; ++i)
                weights[i] = (int8_t)((i * 89u + kernel * 127u) & 255u);
            /* Deliberately leave a different kernel in all hardware lanes. */
            if (ai_dot9_packed(0, 0, 0, 0xffffffffu, 0xffffffffu, 0xffu) != 0)
                return 1;
            ai_load_1x1_weights(weights, channels);
            uint32_t resident[3] = {AI_WGT0, AI_WGT1, AI_WGT2};
            for (uint32_t lane = channels; lane < 9; ++lane)
                if ((resident[lane >> 2] >> ((lane & 3u) * 8u)) & 255u) return 5;
            if (resident[2] & 0xffffff00u) return 6;
            for (uint32_t pixel = 0; pixel < 34; pixel += 2) {
                int32_t expected = 0;
                for (uint32_t lane = 0; lane < channels; ++lane)
                    expected += (int32_t)pixels[lane * 35 + pixel] * weights[lane];
                int32_t actual = ai_dot1x1_loaded(pixels, 35, pixel, channels);
                if (actual != expected) {
                    uart_puts("AI_WEIGHT_REUSE_FAIL channels="); uart_putdec(channels);
                    uart_puts(" kernel="); uart_putdec(kernel);
                    uart_puts(" pixel="); uart_putdec(pixel); uart_putc('\n');
                    return 2;
                }
                ++cases;
            }
            if (AI_WGT0 != resident[0] || AI_WGT1 != resident[1] || AI_WGT2 != resident[2])
                return 7;
        }
    }
    uart_puts("AI_WEIGHT_REUSE_PASS cases="); uart_putdec(cases); uart_putc('\n');
    return cases == 612 ? 0 : 3;
}
