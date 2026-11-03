/* Sequential ownership of the AI unit extends across every pixel in a tile. */
#ifndef AI_MAC_TILE_H
#define AI_MAC_TILE_H
#include "ai_mac_reuse.h"
#include "ai_mac_prepack.h"

static inline void ai_load_prepacked_weights(const uint32_t packed[3])
{
#ifdef YOLO_HOST_TEST
    host_resident_weights[0] = packed[0];
    host_resident_weights[1] = packed[1];
    host_resident_weights[2] = packed[2];
#else
    AI_WGT0 = packed[0]; AI_WGT1 = packed[1]; AI_WGT2 = packed[2];
#endif
}
#endif
