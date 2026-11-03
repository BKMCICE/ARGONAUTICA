/* Experimental exact INT8 residual requantization. No production dispatch yet. */
#ifndef INT8_SHORTCUT_LUT_H
#define INT8_SHORTCUT_LUT_H
#include <stdint.h>
typedef struct { int16_t values[2][256]; } Int8ShortcutLut;

/* Caller owns scratch, separate from the tensors. Input/output may be exactly
 * aliased; partial overlap is not supported. All multipliers are signed32 Q24.
 * |int8 * signed32 / 2^24| <= 16384, including INT8_MIN/INT32_MIN,
 * so each rounded term fits int16 and their sum fits signed32.
 * apply_q24() and clip8() are the unchanged production helpers, defined first.
 */
#ifndef INT8_SHORTCUT_LUT_TYPES_ONLY
static void int8_shortcut_lut(const int8_t *input, const int8_t *source,
                             int8_t *output, uint32_t count,
                             int32_t previous_q24, int32_t source_q24,
                             Int8ShortcutLut *scratch)
{
    if (!count) return;
    for (uint32_t i = 0; i < 256; ++i) {
        int32_t value = i < 128 ? (int32_t)i : (int32_t)i - 256;
        scratch->values[0][i] = (int16_t)apply_q24(value, previous_q24);
        scratch->values[1][i] = (int16_t)apply_q24(value, source_q24);
    }
    for (uint32_t i = 0; i < count; ++i) {
        int32_t value = (int32_t)scratch->values[0][(uint8_t)input[i]] +
                        (int32_t)scratch->values[1][(uint8_t)source[i]];
        output[i] = clip8(value);
    }
}
#endif
#endif
