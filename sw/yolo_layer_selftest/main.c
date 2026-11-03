#include "soc.h"
#include "model_graph.h"
#include "layer_cache.h"

int main(void)
{
    struct { uint32_t before; YoloLayer layer; uint32_t after; } local;
    local.before = 0x13579bdf;
    local.after = 0x2468ace0;
    if (!yolo_layer_cache_range(&local.layer) ||
        yolo_layer_cache_range((const YoloLayer *)0xe000) ||
        yolo_layer_cache_range((const YoloLayer *)(0x10000-sizeof(YoloLayer)+1))) return 5;
    for (uint32_t index=0;index<YOLO_LAYER_COUNT;++index) {
        if (!yolo_layer_stage(&local.layer,&yolo_layers[index])) return 6;
        const unsigned char *a=(const unsigned char *)&local.layer;
        const unsigned char *b=(const unsigned char *)&yolo_layers[index];
        for (uint32_t byte=0;byte<sizeof(YoloLayer);++byte) if(a[byte]!=b[byte]) return 7;
        if (local.before!=0x13579bdf || local.after!=0x2468ace0) return 8;
    }
    uart_puts("YOLO_LAYER_SELFTEST local=0x"); uart_puthex((uintptr_t)&local.layer);
    uart_puts(" copies="); uart_putdec(YOLO_LAYER_COUNT); uart_puts(" PASS\n");
    return 0;
}
