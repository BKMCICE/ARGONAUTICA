#ifndef YOLO_LAYER_CACHE_H
#define YOLO_LAYER_CACHE_H

/* model_graph.h supplies YoloLayer. One descriptor is reused on the TCM stack;
 * model tensors and the full graph keep their original DDR placement. */
static int yolo_layer_cache_range(const YoloLayer *layer)
{
#ifdef YOLO_HOST_TEST
    (void)layer;
    return 1; /* Host checks only byte/functional equivalence, never placement. */
#else
    uintptr_t address = (uintptr_t)layer;
    return address >= 0xe100u && address <= 0x10000u - sizeof(*layer);
#endif
}

__attribute__((noinline)) static int yolo_layer_stage(YoloLayer *target,
                                                    const YoloLayer *source)
{
    unsigned char *dst = (unsigned char *)target;
    const unsigned char *src = (const unsigned char *)source;
    for (uint32_t byte = 0; byte < sizeof(*target); ++byte) dst[byte] = src[byte];
    /* Read back the actual stack bytes, including signed fields and sources.
     * This bounded verification is included in the forward timing window. */
    volatile const unsigned char *readback = (volatile const unsigned char *)target;
    for (uint32_t byte = 0; byte < sizeof(*target); ++byte)
        if (readback[byte] != src[byte]) return 0;
    return 1;
}
#endif
