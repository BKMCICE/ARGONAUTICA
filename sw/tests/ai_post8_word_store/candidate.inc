/* Generated exact body, only function namespace and one store loop. */
__attribute__((noinline)) static int a79_placebo_block(const YoloLayer *layer,
    const int8_t *input, int8_t *output, const int8_t *kernels,
    const int32_t *params, uint32_t in_group, uint32_t out_group)
{
    if (!layer || !input || !output || !kernels || !params ||
        layer->kind != YOLO_CONV || layer->size != 1 || layer->pad ||
        !layer->groups || !layer->stride || !layer->ih || !layer->iw ||
        !layer->oh || !layer->ow || !in_group || in_group > 224u || !out_group ||
        layer->ic / layer->groups != in_group || layer->ic % layer->groups ||
        layer->oc / layer->groups != out_group || layer->oc % layer->groups ||
        layer->iw > UINT32_MAX / layer->ih ||
        layer->ow > UINT32_MAX / layer->oh ||
        layer->oh - 1u > (layer->ih - 1u) / layer->stride ||
        layer->ow - 1u > (layer->iw - 1u) / layer->stride)
        return AI_BLOCK_BAD_SHAPE;
    uint32_t plane = layer->ih * layer->iw;
    uint32_t out_plane = layer->oh * layer->ow;
    if (layer->ic > UINT32_MAX / plane || layer->oc > UINT32_MAX / out_plane ||
        layer->oc > UINT32_MAX / in_group || layer->oc > UINT32_MAX / 8u)
        return AI_BLOCK_BAD_SHAPE;
#if YOLO_BLOCK_Q24_REUSE || YOLO_BLOCK_POST8
    /* Hoisted reads require output to be independent of the source objects.
     * Reject before any MMIO or output write; the flag0 path is unchanged. */
    uint32_t output_bytes = layer->oc * out_plane;
    if (!block_q24_disjoint(output, output_bytes, input, layer->ic * plane) ||
        !block_q24_disjoint(output, output_bytes, kernels, layer->oc * in_group) ||
        !block_q24_disjoint(output, output_bytes, params, layer->oc * 8u) ||
        !block_q24_disjoint(output, output_bytes, layer, sizeof(*layer)))
        return AI_BLOCK_BAD_SHAPE;
#endif
#if YOLO_BLOCK_INPUT_CACHE
    uint32_t blocks = (in_group + 8u) / 9u;
    /* Capacity fallback keeps the original block path. Reject scratch overlap
     * before MMIO or prepacking; overflow-safe sizes were checked above. */
    uint32_t use_cache = out_group > 4u && out_plane <= BLOCK_INPUT_CACHE_WORDS / (blocks * 3u);
    if (use_cache && (!block_cache_disjoint(input, layer->ic * plane) ||
        !block_cache_disjoint(output, layer->oc * out_plane) ||
        !block_cache_disjoint(kernels, layer->oc * in_group) ||
        !block_cache_disjoint(params, layer->oc * 8u)))
        return AI_BLOCK_BAD_SHAPE;
#endif
    if (AI_BLOCK_READ(AI_BLOCK_REG_ID) != AI_BLOCK_ID) return AI_BLOCK_UNSUPPORTED;
    if (AI_BLOCK_READ(AI_BLOCK_CTRL) & 1u) return AI_BLOCK_HW_ERROR;
#if YOLO_BLOCK8
    /* Probe before any writes. Old A02 returns zero at this read-only offset;
     * errors after submitting a task still propagate without retry/fallback. */
    uint32_t output_capacity = AI_BLOCK_READ(0x28u) == 0x41333331u ? 8u : 4u;
#else
#define output_capacity 4u
#endif
#if YOLO_BLOCK_POST8
    /* Distinct read-only capability: A331 alone never enables postprocessing.
     * All fallback selection happens before the first MMIO/output write. */
    uint32_t post_id = AI_BLOCK_READ(0x2cu);
    if ((post_id && post_id != 0x41343831u) ||
        (post_id && output_capacity != 8u)) return AI_BLOCK_HW_ERROR;
    uint32_t use_post = post_id != 0;
    if (use_post) AI_BLOCK_WRITE(0x204u, 1u | (layer->leaky ? 2u : 0u));
#endif
#if !YOLO_BLOCK_INPUT_CACHE
    uint32_t blocks = (in_group + 8u) / 9u;
#endif
    uint32_t last = in_group - (blocks - 1u) * 9u;
    uint32_t packed[3];
#if !YOLO_BLOCK_POST8
    int32_t acc[YOLO_BLOCK8 ? 64 : 32];
#endif
#if YOLO_BLOCK_PHASE_PROFILE
    BlockPhaseStat *phase_stat = &block_phase_stats[block_phase_index];
#endif
    for (uint32_t group = 0; group < layer->groups; ++group) {
        const int8_t *group_input = input + group * in_group * plane;
#if YOLO_BLOCK_INPUT_CACHE
        if (use_cache) {
#if YOLO_BLOCK_CACHE_PHASE_PROFILE
            uint32_t cache_start = block_phase_clock();
#endif
            block_cache_pack(layer, group_input, plane, out_plane, in_group, blocks);
#if YOLO_BLOCK_CACHE_PHASE_PROFILE
            phase_stat->cache_cycles += (uint32_t)(block_phase_clock() - cache_start);
#endif
        }
#endif
        for (uint32_t oc_base = 0; oc_base < out_group; oc_base += output_capacity) {
            uint32_t outputs = out_group - oc_base;
            if (outputs > output_capacity) outputs = output_capacity;
#if YOLO_BLOCK_PHASE_PROFILE
            uint32_t weight_start = block_phase_clock();
#endif
            AI_BLOCK_WRITE(AI_BLOCK_CTRL, 4u);
            AI_BLOCK_WRITE(AI_BLOCK_WADDR, 0u);
#if YOLO_BLOCK_POST8
            if (use_post) AI_BLOCK_WRITE(0x208u, 0u);
#endif
            for (uint32_t ch = 0; ch < outputs; ++ch) {
                uint32_t oc = group * out_group + oc_base + ch;
#if YOLO_BLOCK_POST8
                if (use_post) {
                    AI_BLOCK_WRITE(0x20cu, (uint32_t)params[oc * 2]);
                    AI_BLOCK_WRITE(0x210u, (uint32_t)params[oc * 2 + 1]);
                }
#endif
                for (uint32_t b = 0; b < blocks; ++b) {
                    uint32_t count = in_group - b * 9u;
                    if (count > 9u) count = 9u;
                    ai_pack_1x1_weights(kernels + oc * in_group + b * 9u, count, packed);
                    for (uint32_t word = 0; word < 3u; ++word)
                        AI_BLOCK_WRITE(AI_BLOCK_WDATA, packed[word]);
                }
            }
#if YOLO_BLOCK_PHASE_PROFILE
            phase_stat->weight_cycles += (uint32_t)(block_phase_clock() - weight_start);
            ++phase_stat->batches;
            phase_stat->weight_words += outputs * blocks * 3u;
#endif
            for (uint32_t oy = 0; oy < layer->oh; ++oy) {
                for (uint32_t ox = 0; ox < layer->ow;) {
                    uint32_t pixels = layer->ow - ox;
                    if (pixels > 8u) pixels = 8u;
                    uint32_t first = oy * layer->stride * layer->iw + ox * layer->stride;
#if YOLO_BLOCK_PHASE_PROFILE
                    uint32_t phase_sample = !(phase_stat->tasks++ & 63u) ||
                        (oy + 1u == layer->oh && ox + pixels == layer->ow &&
                         oc_base + outputs == out_group);
                    uint32_t phase_start = 0, task_start = 0;
                    if (phase_sample) task_start = block_phase_clock();
                    BLOCK_PHASE_BEGIN();
#endif
                    AI_BLOCK_WRITE(AI_BLOCK_CTRL, 4u);
                    AI_BLOCK_WRITE(AI_BLOCK_PADDR, 0u);
#if YOLO_BLOCK_PHASE_PROFILE
                    BLOCK_PHASE_END(BP_SETUP);
#endif
                    for (uint32_t b = 0; b < blocks; ++b) {
#if YOLO_BLOCK_INPUT_CACHE
                        if (use_cache) {
#if YOLO_BLOCK_CACHE_PHASE_PROFILE
                            BLOCK_PHASE_BEGIN();
#endif
                            const uint32_t *src = block_input_cache +
                                (b * out_plane + oy * layer->ow + ox) * 3u;
                            for (uint32_t p = 0; p < pixels; ++p) {
                                AI_BLOCK_WRITE(AI_BLOCK_PDATA, src[0]);
                                AI_BLOCK_WRITE(AI_BLOCK_PDATA, src[1]);
                                AI_BLOCK_WRITE(AI_BLOCK_PDATA, src[2]);
                                src += 3;
                            }
#if YOLO_BLOCK_CACHE_PHASE_PROFILE
                            BLOCK_PHASE_END(BP_WRITE);
#endif
                            continue;
                        }
#endif
                        uint32_t count = in_group - b * 9u;
                        if (count > 9u) count = 9u;
                        for (uint32_t p = 0; p < pixels; ++p) {
#if YOLO_BLOCK_PHASE_PROFILE
                            BLOCK_PHASE_BEGIN();
#endif
                            ai_pack_1x1_input(group_input + b * 9u * plane, plane,
                                first + p * layer->stride, count, packed);
#if YOLO_BLOCK_PHASE_PROFILE
                            BLOCK_PHASE_END(BP_PACK);
                            BLOCK_PHASE_BEGIN();
#endif
                            for (uint32_t word = 0; word < 3u; ++word)
                                AI_BLOCK_WRITE(AI_BLOCK_PDATA, packed[word]);
#if YOLO_BLOCK_PHASE_PROFILE
                            BLOCK_PHASE_END(BP_WRITE);
#endif
                        }
                    }
#if YOLO_BLOCK_PHASE_PROFILE
                    BLOCK_PHASE_BEGIN();
#endif
                    AI_BLOCK_WRITE(AI_BLOCK_SHAPE, pixels | (outputs << 4) |
                        (blocks << 8) | (last << 16));
                    AI_BLOCK_WRITE(AI_BLOCK_CTRL, 1u);
                    uint32_t status = 0, polls = 0;
                    do { status = AI_BLOCK_READ(AI_BLOCK_CTRL); ++polls; }
                    while (!(status & 2u) && polls < 100000u);
                    if (!(status & 2u)) return AI_BLOCK_TIMEOUT;
                    if (status & 5u) return AI_BLOCK_HW_ERROR;
#if YOLO_BLOCK_PHASE_PROFILE
                    BLOCK_PHASE_END(BP_WAIT);
                    BLOCK_PHASE_BEGIN();
#endif
#if YOLO_BLOCK_POST8
                    if (use_post) {
                        AI_BLOCK_WRITE(0x21cu, 0u);
                        for (uint32_t ch = 0; ch < outputs; ++ch) {
                            uint32_t oc = group * out_group + oc_base + ch;
                            int8_t *dest = output + oc * out_plane + oy * layer->ow + ox;
                            for (uint32_t p = 0; p < pixels;) {
                                uint32_t word = AI_BLOCK_READ(0x220u);
                                uint32_t count = pixels - p;
                                if (count > 4u) count = 4u;
                                for (uint32_t byte = 0; byte < count; ++byte) {
                                    dest[p++] = (int8_t)word;
                                    word >>= 8;
                                }
                            }
                        }
                        if (AI_BLOCK_READ(AI_BLOCK_CTRL) & 4u) return AI_BLOCK_HW_ERROR;
                    } else {
                        uint32_t oc = group * out_group + oc_base;
                        int rc = block_post8_raw_store(
                            output + oc * out_plane + oy * layer->ow + ox,
                            out_plane, params + oc * 2, pixels, outputs, layer->leaky);
                        if (rc) return rc;
#else
                    AI_BLOCK_WRITE(AI_BLOCK_RADDR, 0u);
                    for (uint32_t i = 0; i < outputs * pixels; ++i)
                        acc[i] = (int32_t)AI_BLOCK_READ(AI_BLOCK_RDATA);
                    if (AI_BLOCK_READ(AI_BLOCK_CTRL) & 4u) return AI_BLOCK_HW_ERROR;
#if YOLO_BLOCK_PHASE_PROFILE
                    BLOCK_PHASE_END(BP_READ);
                    BLOCK_PHASE_BEGIN();
#endif
                    for (uint32_t ch = 0; ch < outputs; ++ch) {
                        uint32_t oc = group * out_group + oc_base + ch;
#if YOLO_BLOCK_Q24_REUSE
                        block_q24_store(acc + ch * pixels,
                            output + oc * out_plane + oy * layer->ow + ox,
                            pixels, params[oc * 2], params[oc * 2 + 1], layer->leaky);
#else
                        for (uint32_t p = 0; p < pixels; ++p) {
                            int32_t value = apply_q24(acc[ch * pixels + p], params[oc * 2]) + params[oc * 2 + 1];
                            if (layer->leaky && value < 0) value = apply_q24(value, YOLO_LEAKY_Q24);
                            output[oc * out_plane + oy * layer->ow + ox + p] = clip8(value);
                        }
#endif
                    }
#endif
#if YOLO_BLOCK_POST8
                    }
#endif
#if YOLO_BLOCK_PHASE_PROFILE
                    BLOCK_PHASE_END(BP_Q24);
                    if (phase_sample) {
                        uint32_t elapsed = block_phase_clock() - task_start;
                        phase_stat->task_cycles += elapsed;
                        if (elapsed > phase_stat->max_task) phase_stat->max_task = elapsed;
                        ++phase_stat->samples;
                        phase_stat->vectors += blocks * pixels;
                        phase_stat->input_words += blocks * pixels * 3u;
                        phase_stat->result_words += outputs *
#if YOLO_BLOCK_POST8
                            (use_post ? (pixels + 3u) / 4u : pixels);
#else
                            pixels;
#endif
                        phase_stat->polls += polls;
                        phase_stat->engine_cycles += AI_BLOCK_READ(AI_BLOCK_CYCLES);
                        phase_stat->dots += AI_BLOCK_READ(AI_BLOCK_DOTS);
                    }
#endif
                    ox += pixels;
                }
            }
        }
    }
#if YOLO_BLOCK_POST8
    if (use_post) AI_BLOCK_WRITE(0x204u, 0u);
#endif
    return AI_BLOCK_OK;
#if !YOLO_BLOCK8
#undef output_capacity
#endif
}

__attribute__((noinline)) static int a79_word_block(const YoloLayer *layer,
    const int8_t *input, int8_t *output, const int8_t *kernels,
    const int32_t *params, uint32_t in_group, uint32_t out_group)
{
    if (!layer || !input || !output || !kernels || !params ||
        layer->kind != YOLO_CONV || layer->size != 1 || layer->pad ||
        !layer->groups || !layer->stride || !layer->ih || !layer->iw ||
        !layer->oh || !layer->ow || !in_group || in_group > 224u || !out_group ||
        layer->ic / layer->groups != in_group || layer->ic % layer->groups ||
        layer->oc / layer->groups != out_group || layer->oc % layer->groups ||
        layer->iw > UINT32_MAX / layer->ih ||
        layer->ow > UINT32_MAX / layer->oh ||
        layer->oh - 1u > (layer->ih - 1u) / layer->stride ||
        layer->ow - 1u > (layer->iw - 1u) / layer->stride)
        return AI_BLOCK_BAD_SHAPE;
    uint32_t plane = layer->ih * layer->iw;
    uint32_t out_plane = layer->oh * layer->ow;
    if (layer->ic > UINT32_MAX / plane || layer->oc > UINT32_MAX / out_plane ||
        layer->oc > UINT32_MAX / in_group || layer->oc > UINT32_MAX / 8u)
        return AI_BLOCK_BAD_SHAPE;
#if YOLO_BLOCK_Q24_REUSE || YOLO_BLOCK_POST8
    /* Hoisted reads require output to be independent of the source objects.
     * Reject before any MMIO or output write; the flag0 path is unchanged. */
    uint32_t output_bytes = layer->oc * out_plane;
    if (!block_q24_disjoint(output, output_bytes, input, layer->ic * plane) ||
        !block_q24_disjoint(output, output_bytes, kernels, layer->oc * in_group) ||
        !block_q24_disjoint(output, output_bytes, params, layer->oc * 8u) ||
        !block_q24_disjoint(output, output_bytes, layer, sizeof(*layer)))
        return AI_BLOCK_BAD_SHAPE;
#endif
#if YOLO_BLOCK_INPUT_CACHE
    uint32_t blocks = (in_group + 8u) / 9u;
    /* Capacity fallback keeps the original block path. Reject scratch overlap
     * before MMIO or prepacking; overflow-safe sizes were checked above. */
    uint32_t use_cache = out_group > 4u && out_plane <= BLOCK_INPUT_CACHE_WORDS / (blocks * 3u);
    if (use_cache && (!block_cache_disjoint(input, layer->ic * plane) ||
        !block_cache_disjoint(output, layer->oc * out_plane) ||
        !block_cache_disjoint(kernels, layer->oc * in_group) ||
        !block_cache_disjoint(params, layer->oc * 8u)))
        return AI_BLOCK_BAD_SHAPE;
#endif
    if (AI_BLOCK_READ(AI_BLOCK_REG_ID) != AI_BLOCK_ID) return AI_BLOCK_UNSUPPORTED;
    if (AI_BLOCK_READ(AI_BLOCK_CTRL) & 1u) return AI_BLOCK_HW_ERROR;
#if YOLO_BLOCK8
    /* Probe before any writes. Old A02 returns zero at this read-only offset;
     * errors after submitting a task still propagate without retry/fallback. */
    uint32_t output_capacity = AI_BLOCK_READ(0x28u) == 0x41333331u ? 8u : 4u;
#else
#define output_capacity 4u
#endif
#if YOLO_BLOCK_POST8
    /* Distinct read-only capability: A331 alone never enables postprocessing.
     * All fallback selection happens before the first MMIO/output write. */
    uint32_t post_id = AI_BLOCK_READ(0x2cu);
    if ((post_id && post_id != 0x41343831u) ||
        (post_id && output_capacity != 8u)) return AI_BLOCK_HW_ERROR;
    uint32_t use_post = post_id != 0;
    if (use_post) AI_BLOCK_WRITE(0x204u, 1u | (layer->leaky ? 2u : 0u));
#endif
#if !YOLO_BLOCK_INPUT_CACHE
    uint32_t blocks = (in_group + 8u) / 9u;
#endif
    uint32_t last = in_group - (blocks - 1u) * 9u;
    uint32_t packed[3];
#if !YOLO_BLOCK_POST8
    int32_t acc[YOLO_BLOCK8 ? 64 : 32];
#endif
#if YOLO_BLOCK_PHASE_PROFILE
    BlockPhaseStat *phase_stat = &block_phase_stats[block_phase_index];
#endif
    for (uint32_t group = 0; group < layer->groups; ++group) {
        const int8_t *group_input = input + group * in_group * plane;
#if YOLO_BLOCK_INPUT_CACHE
        if (use_cache) {
#if YOLO_BLOCK_CACHE_PHASE_PROFILE
            uint32_t cache_start = block_phase_clock();
#endif
            block_cache_pack(layer, group_input, plane, out_plane, in_group, blocks);
#if YOLO_BLOCK_CACHE_PHASE_PROFILE
            phase_stat->cache_cycles += (uint32_t)(block_phase_clock() - cache_start);
#endif
        }
#endif
        for (uint32_t oc_base = 0; oc_base < out_group; oc_base += output_capacity) {
            uint32_t outputs = out_group - oc_base;
            if (outputs > output_capacity) outputs = output_capacity;
#if YOLO_BLOCK_PHASE_PROFILE
            uint32_t weight_start = block_phase_clock();
#endif
            AI_BLOCK_WRITE(AI_BLOCK_CTRL, 4u);
            AI_BLOCK_WRITE(AI_BLOCK_WADDR, 0u);
#if YOLO_BLOCK_POST8
            if (use_post) AI_BLOCK_WRITE(0x208u, 0u);
#endif
            for (uint32_t ch = 0; ch < outputs; ++ch) {
                uint32_t oc = group * out_group + oc_base + ch;
#if YOLO_BLOCK_POST8
                if (use_post) {
                    AI_BLOCK_WRITE(0x20cu, (uint32_t)params[oc * 2]);
                    AI_BLOCK_WRITE(0x210u, (uint32_t)params[oc * 2 + 1]);
                }
#endif
                for (uint32_t b = 0; b < blocks; ++b) {
                    uint32_t count = in_group - b * 9u;
                    if (count > 9u) count = 9u;
                    ai_pack_1x1_weights(kernels + oc * in_group + b * 9u, count, packed);
                    for (uint32_t word = 0; word < 3u; ++word)
                        AI_BLOCK_WRITE(AI_BLOCK_WDATA, packed[word]);
                }
            }
#if YOLO_BLOCK_PHASE_PROFILE
            phase_stat->weight_cycles += (uint32_t)(block_phase_clock() - weight_start);
            ++phase_stat->batches;
            phase_stat->weight_words += outputs * blocks * 3u;
#endif
            for (uint32_t oy = 0; oy < layer->oh; ++oy) {
                for (uint32_t ox = 0; ox < layer->ow;) {
                    uint32_t pixels = layer->ow - ox;
                    if (pixels > 8u) pixels = 8u;
                    uint32_t first = oy * layer->stride * layer->iw + ox * layer->stride;
#if YOLO_BLOCK_PHASE_PROFILE
                    uint32_t phase_sample = !(phase_stat->tasks++ & 63u) ||
                        (oy + 1u == layer->oh && ox + pixels == layer->ow &&
                         oc_base + outputs == out_group);
                    uint32_t phase_start = 0, task_start = 0;
                    if (phase_sample) task_start = block_phase_clock();
                    BLOCK_PHASE_BEGIN();
#endif
                    AI_BLOCK_WRITE(AI_BLOCK_CTRL, 4u);
                    AI_BLOCK_WRITE(AI_BLOCK_PADDR, 0u);
#if YOLO_BLOCK_PHASE_PROFILE
                    BLOCK_PHASE_END(BP_SETUP);
#endif
                    for (uint32_t b = 0; b < blocks; ++b) {
#if YOLO_BLOCK_INPUT_CACHE
                        if (use_cache) {
#if YOLO_BLOCK_CACHE_PHASE_PROFILE
                            BLOCK_PHASE_BEGIN();
#endif
                            const uint32_t *src = block_input_cache +
                                (b * out_plane + oy * layer->ow + ox) * 3u;
                            for (uint32_t p = 0; p < pixels; ++p) {
                                AI_BLOCK_WRITE(AI_BLOCK_PDATA, src[0]);
                                AI_BLOCK_WRITE(AI_BLOCK_PDATA, src[1]);
                                AI_BLOCK_WRITE(AI_BLOCK_PDATA, src[2]);
                                src += 3;
                            }
#if YOLO_BLOCK_CACHE_PHASE_PROFILE
                            BLOCK_PHASE_END(BP_WRITE);
#endif
                            continue;
                        }
#endif
                        uint32_t count = in_group - b * 9u;
                        if (count > 9u) count = 9u;
                        for (uint32_t p = 0; p < pixels; ++p) {
#if YOLO_BLOCK_PHASE_PROFILE
                            BLOCK_PHASE_BEGIN();
#endif
                            ai_pack_1x1_input(group_input + b * 9u * plane, plane,
                                first + p * layer->stride, count, packed);
#if YOLO_BLOCK_PHASE_PROFILE
                            BLOCK_PHASE_END(BP_PACK);
                            BLOCK_PHASE_BEGIN();
#endif
                            for (uint32_t word = 0; word < 3u; ++word)
                                AI_BLOCK_WRITE(AI_BLOCK_PDATA, packed[word]);
#if YOLO_BLOCK_PHASE_PROFILE
                            BLOCK_PHASE_END(BP_WRITE);
#endif
                        }
                    }
#if YOLO_BLOCK_PHASE_PROFILE
                    BLOCK_PHASE_BEGIN();
#endif
                    AI_BLOCK_WRITE(AI_BLOCK_SHAPE, pixels | (outputs << 4) |
                        (blocks << 8) | (last << 16));
                    AI_BLOCK_WRITE(AI_BLOCK_CTRL, 1u);
                    uint32_t status = 0, polls = 0;
                    do { status = AI_BLOCK_READ(AI_BLOCK_CTRL); ++polls; }
                    while (!(status & 2u) && polls < 100000u);
                    if (!(status & 2u)) return AI_BLOCK_TIMEOUT;
                    if (status & 5u) return AI_BLOCK_HW_ERROR;
#if YOLO_BLOCK_PHASE_PROFILE
                    BLOCK_PHASE_END(BP_WAIT);
                    BLOCK_PHASE_BEGIN();
#endif
#if YOLO_BLOCK_POST8
                    if (use_post) {
                        AI_BLOCK_WRITE(0x21cu, 0u);
                        for (uint32_t ch = 0; ch < outputs; ++ch) {
                            uint32_t oc = group * out_group + oc_base + ch;
                            int8_t *dest = output + oc * out_plane + oy * layer->ow + ox;
                            for (uint32_t p = 0; p < pixels;) {
                                uint32_t word = AI_BLOCK_READ(0x220u);
                                uint32_t count = pixels - p;
                                if (count > 4u) count = 4u;
                                a79_store(dest+p,word,count);
                                p+=count;
                            }
                        }
                        if (AI_BLOCK_READ(AI_BLOCK_CTRL) & 4u) return AI_BLOCK_HW_ERROR;
                    } else {
                        uint32_t oc = group * out_group + oc_base;
                        int rc = block_post8_raw_store(
                            output + oc * out_plane + oy * layer->ow + ox,
                            out_plane, params + oc * 2, pixels, outputs, layer->leaky);
                        if (rc) return rc;
#else
                    AI_BLOCK_WRITE(AI_BLOCK_RADDR, 0u);
                    for (uint32_t i = 0; i < outputs * pixels; ++i)
                        acc[i] = (int32_t)AI_BLOCK_READ(AI_BLOCK_RDATA);
                    if (AI_BLOCK_READ(AI_BLOCK_CTRL) & 4u) return AI_BLOCK_HW_ERROR;
#if YOLO_BLOCK_PHASE_PROFILE
                    BLOCK_PHASE_END(BP_READ);
                    BLOCK_PHASE_BEGIN();
#endif
                    for (uint32_t ch = 0; ch < outputs; ++ch) {
                        uint32_t oc = group * out_group + oc_base + ch;
#if YOLO_BLOCK_Q24_REUSE
                        block_q24_store(acc + ch * pixels,
                            output + oc * out_plane + oy * layer->ow + ox,
                            pixels, params[oc * 2], params[oc * 2 + 1], layer->leaky);
#else
                        for (uint32_t p = 0; p < pixels; ++p) {
                            int32_t value = apply_q24(acc[ch * pixels + p], params[oc * 2]) + params[oc * 2 + 1];
                            if (layer->leaky && value < 0) value = apply_q24(value, YOLO_LEAKY_Q24);
                            output[oc * out_plane + oy * layer->ow + ox + p] = clip8(value);
                        }
#endif
                    }
#endif
#if YOLO_BLOCK_POST8
                    }
#endif
#if YOLO_BLOCK_PHASE_PROFILE
                    BLOCK_PHASE_END(BP_Q24);
                    if (phase_sample) {
                        uint32_t elapsed = block_phase_clock() - task_start;
                        phase_stat->task_cycles += elapsed;
                        if (elapsed > phase_stat->max_task) phase_stat->max_task = elapsed;
                        ++phase_stat->samples;
                        phase_stat->vectors += blocks * pixels;
                        phase_stat->input_words += blocks * pixels * 3u;
                        phase_stat->result_words += outputs *
#if YOLO_BLOCK_POST8
                            (use_post ? (pixels + 3u) / 4u : pixels);
#else
                            pixels;
#endif
                        phase_stat->polls += polls;
                        phase_stat->engine_cycles += AI_BLOCK_READ(AI_BLOCK_CYCLES);
                        phase_stat->dots += AI_BLOCK_READ(AI_BLOCK_DOTS);
                    }
#endif
                    ox += pixels;
                }
            }
        }
    }
#if YOLO_BLOCK_POST8
    if (use_post) AI_BLOCK_WRITE(0x204u, 0u);
#endif
    return AI_BLOCK_OK;
#if !YOLO_BLOCK8
#undef output_capacity
#endif
}
