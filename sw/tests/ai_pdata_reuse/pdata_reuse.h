/* A28 diagnostic only. Retain PDATA across output batches; reload packed
 * weights for every spatial tile. All preparation is inside operator timing.
 * Exclusive ownership of AI and both static caches is required for the call.
 */
#ifndef A28_PDATA_REUSE_H
#define A28_PDATA_REUSE_H
#define A28_WEIGHT_WORDS (255u * 25u * 3u)
static uint32_t a28_weight_cache[A28_WEIGHT_WORDS] __attribute__((aligned(32)));
__attribute__((noinline)) static int a28_reuse(const YoloLayer *layer,
    const int8_t *input, int8_t *output, const int8_t *kernels,
    const int32_t *params)
{
    if (!layer || !input || !output || !kernels || !params ||
        layer->kind != YOLO_CONV || layer->size != 1 || layer->pad ||
        !layer->groups || !layer->stride || !layer->ih || !layer->iw ||
        !layer->oh || !layer->ow || !layer->ic || !layer->oc ||
        layer->ic % layer->groups || layer->oc % layer->groups ||
        layer->iw > UINT32_MAX / layer->ih ||
        layer->ow > UINT32_MAX / layer->oh ||
        layer->oh - 1u > (layer->ih - 1u) / layer->stride ||
        layer->ow - 1u > (layer->iw - 1u) / layer->stride)
        return AI_BLOCK_BAD_SHAPE;
    uint32_t ci = layer->ic / layer->groups, co = layer->oc / layer->groups;
    if (!ci || ci > 224u || !co || co > 255u) return AI_BLOCK_BAD_SHAPE;
    uint32_t plane = layer->ih * layer->iw, op = layer->oh * layer->ow;
    if (layer->ic > UINT32_MAX / plane || layer->oc > UINT32_MAX / op ||
        layer->oc > UINT32_MAX / ci || layer->oc > UINT32_MAX / 8u)
        return AI_BLOCK_BAD_SHAPE;
    uint32_t blocks = (ci + 8u) / 9u;
    if (op > BLOCK_INPUT_CACHE_WORDS / (blocks * 3u)) return AI_BLOCK_BAD_SHAPE;
    const void *objects[] = {input, output, kernels, params, layer};
    uint32_t sizes[] = {layer->ic * plane, layer->oc * op, layer->oc * ci,
        layer->oc * 8u, sizeof(*layer)};
    for (uint32_t i = 0; i < 5u; ++i) {
        if (!block_cache_disjoint(objects[i], sizes[i]) ||
            !block_q24_disjoint(objects[i], sizes[i], a28_weight_cache,
                sizeof(a28_weight_cache)) ||
            (i != 1u && !block_q24_disjoint(output, sizes[1], objects[i], sizes[i])))
            return AI_BLOCK_BAD_SHAPE;
    }
    if (AI_BLOCK_READ(AI_BLOCK_REG_ID) != AI_BLOCK_ID) return AI_BLOCK_UNSUPPORTED;
    if (AI_BLOCK_READ(AI_BLOCK_CTRL) & 1u) return AI_BLOCK_HW_ERROR;
    uint32_t last = ci - (blocks - 1u) * 9u;
    int32_t acc[32];
    for (uint32_t g = 0; g < layer->groups; ++g) {
        block_cache_pack(layer, input + g * ci * plane, plane, op, ci, blocks);
        for (uint32_t ch = 0; ch < co; ++ch)
            for (uint32_t b = 0; b < blocks; ++b) {
                uint32_t count = ci - b * 9u;
                if (count > 9u) count = 9u;
                ai_pack_1x1_weights(kernels + (g * co + ch) * ci + b * 9u,
                    count, a28_weight_cache + (ch * blocks + b) * 3u);
            }
        for (uint32_t y = 0; y < layer->oh; ++y)
            for (uint32_t x = 0; x < layer->ow;) {
                uint32_t pixels = layer->ow - x;
                if (pixels > 8u) pixels = 8u;
                AI_BLOCK_WRITE(AI_BLOCK_CTRL, 4u);
                AI_BLOCK_WRITE(AI_BLOCK_PADDR, 0u);
                for (uint32_t b = 0; b < blocks; ++b) {
                    const uint32_t *src = block_input_cache +
                        (b * op + y * layer->ow + x) * 3u;
                    for (uint32_t p = 0; p < pixels; ++p) {
                        AI_BLOCK_WRITE(AI_BLOCK_PDATA, src[0]);
                        AI_BLOCK_WRITE(AI_BLOCK_PDATA, src[1]);
                        AI_BLOCK_WRITE(AI_BLOCK_PDATA, src[2]);
                        src += 3;
                    }
                }
                for (uint32_t base = 0; base < co; base += 4u) {
                    uint32_t outputs = co - base;
                    if (outputs > 4u) outputs = 4u;
                    AI_BLOCK_WRITE(AI_BLOCK_CTRL, 4u);
                    AI_BLOCK_WRITE(AI_BLOCK_WADDR, 0u);
                    const uint32_t *src = a28_weight_cache + base * blocks * 3u;
                    for (uint32_t i = 0; i < outputs * blocks * 3u; ++i)
                        AI_BLOCK_WRITE(AI_BLOCK_WDATA, src[i]);
                    AI_BLOCK_WRITE(AI_BLOCK_SHAPE,
                        pixels | (outputs << 4) | (blocks << 8) | (last << 16));
                    AI_BLOCK_WRITE(AI_BLOCK_CTRL, 1u);
                    uint32_t status = 0, polls = 0;
                    do { status = AI_BLOCK_READ(AI_BLOCK_CTRL); ++polls; }
                    while (!(status & 2u) && polls < 100000u);
                    if (!(status & 2u)) return AI_BLOCK_TIMEOUT;
                    if (status & 5u) return AI_BLOCK_HW_ERROR;
                    AI_BLOCK_WRITE(AI_BLOCK_RADDR, 0u);
                    for (uint32_t i = 0; i < outputs * pixels; ++i)
                        acc[i] = (int32_t)AI_BLOCK_READ(AI_BLOCK_RDATA);
                    if (AI_BLOCK_READ(AI_BLOCK_CTRL) & 4u) return AI_BLOCK_HW_ERROR;
                    for (uint32_t ch = 0; ch < outputs; ++ch) {
                        uint32_t oc = g * co + base + ch;
                        block_q24_store(acc + ch * pixels,
                            output + oc * op + y * layer->ow + x,
                            pixels, params[oc * 2], params[oc * 2 + 1], layer->leaky);
                    }
                }
                x += pixels;
            }
    }
    return AI_BLOCK_OK;
}
#endif
