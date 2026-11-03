/* A20 candidate: preserve production Q24/activation semantics while loading
 * multiplier/bias and forming the output pointer once per channel tile.
 * The caller validates output/source disjointness before touching the AI unit.
 */
#ifndef YOLO_BLOCK_Q24_REUSE_H
#define YOLO_BLOCK_Q24_REUSE_H
static inline int block_q24_disjoint(const void *a, uint32_t an,
    const void *b, uint32_t bn)
{
    uintptr_t x = (uintptr_t)a, y = (uintptr_t)b;
    if (!an || !bn || x > UINTPTR_MAX - (an - 1u) ||
        y > UINTPTR_MAX - (bn - 1u)) return 0;
    return x < y ? an <= y - x : bn <= x - y;
}
static inline void block_q24_store(const int32_t *acc, int8_t *dest,
    uint32_t pixels, int32_t multiplier, int32_t bias, uint32_t leaky)
{
    for (uint32_t p = 0; p < pixels; ++p) {
        int32_t value = apply_q24(*acc++, multiplier) + bias;
        if (leaky && value < 0) value = apply_q24(value, YOLO_LEAKY_Q24);
        *dest++ = clip8(value);
    }
}
#endif
