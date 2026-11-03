/* One group's 1x1 input, packed block-major / output-pixel-major, three words
 * per nine signed lanes. Separate static DDR scratch; no TCM/VLA allocation.
 * The operator owns this storage and the AI unit for the duration of a call.
 */
#ifndef YOLO_BLOCK_INPUT_CACHE_H
#define YOLO_BLOCK_INPUT_CACHE_H
#define BLOCK_INPUT_CACHE_WORDS 76800u
static uint32_t block_input_cache[BLOCK_INPUT_CACHE_WORDS] __attribute__((aligned(32)));
#ifdef YOLO_HOST_TEST
uint32_t host_block_cached_groups, host_block_cached_pixels;
#endif
static inline int block_cache_disjoint(const void *ptr, uint32_t bytes)
{
    uintptr_t start = (uintptr_t)ptr, cache = (uintptr_t)block_input_cache;
    if (!bytes || start > UINTPTR_MAX - (bytes - 1u)) return 0;
    return start < cache ? bytes <= cache - start : start - cache >= sizeof(block_input_cache);
}
#if YOLO_CACHE_PACK4
#define BLOCK_CACHE_SCALAR_NAME block_cache_pack_scalar
#else
#define BLOCK_CACHE_SCALAR_NAME block_cache_pack
#endif
__attribute__((noinline)) static void BLOCK_CACHE_SCALAR_NAME(const YoloLayer *layer,
    const int8_t *input, uint32_t plane, uint32_t out_plane, uint32_t channels,
    uint32_t blocks)
{
    for (uint32_t b = 0; b < blocks; ++b) {
        uint32_t count = channels - b * 9u;
        if (count > 9u) count = 9u;
        uint32_t *dest = block_input_cache + b * out_plane * 3u;
        for (uint32_t oy = 0; oy < layer->oh; ++oy) {
            for (uint32_t ox = 0; ox < layer->ow; ++ox) {
                uint32_t pixel = oy * layer->stride * layer->iw + ox * layer->stride;
                ai_pack_1x1_input(input + b * 9u * plane, plane, pixel, count, dest);
                dest += 3;
            }
        }
    }
#ifdef YOLO_HOST_TEST
    ++host_block_cached_groups;
    host_block_cached_pixels += out_plane;
#endif
}
#undef BLOCK_CACHE_SCALAR_NAME
#if YOLO_CACHE_PACK4
#include "cache_pack4.h"
#endif
#endif
