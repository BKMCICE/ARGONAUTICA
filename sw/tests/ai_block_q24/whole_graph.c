/* A21 host-only observer around the unchanged production main.c.
 * Snapshot each CHW output at the existing HOST_LAYER trace point, before
 * arena reuse can overwrite it. No target build includes this file.
 */
#ifndef YOLO_HOST_TEST
#error "whole_graph.c requires YOLO_HOST_TEST"
#endif
#if !YOLO_HOST_TRACE
#error "whole_graph.c requires YOLO_HOST_TRACE=1"
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../ai_1x1_block_layer/host_mmio.h"
#define main a21_production_main
#define uart_puts a21_uart_puts
#define uart_putdec a21_uart_putdec
#include "../../yolo_fixed/main.c"
#undef main
#undef uart_puts
#undef uart_putdec
void uart_puts(const char *);
void uart_putdec(uint32_t);
static FILE *trace;
static unsigned pending, layers;
static void word(uint32_t v)
{
    unsigned char b[4]={(unsigned char)v,(unsigned char)(v>>8),
        (unsigned char)(v>>16),(unsigned char)(v>>24)};
    if(fwrite(b,1,4,trace)!=4)exit(91);
}
void a21_uart_puts(const char *s)
{
    if(!strcmp(s,"HOST_LAYER "))pending=1;
    uart_puts(s);
}
void a21_uart_putdec(uint32_t value)
{
    if(pending){
        if(value!=layers||value>=YOLO_LAYER_COUNT)exit(92);
        const YoloLayer *l=&yolo_layers[value];
        uint32_t n=l->oh*l->ow*l->oc;
        word(value);word(n);
        if(fwrite(output_of((int)value),1,n,trace)!=n)exit(93);
        ++layers;pending=0;
    }
    uart_putdec(value);
}
int main(void)
{
    const char *path=getenv("A21_LAYER_TRACE");
    if(!path||!(trace=fopen(path,"wb")))return 94;
    int result=a21_production_main();
    if(fclose(trace))return 95;
    if(!result&&(layers!=YOLO_LAYER_COUNT||pending))return 96;
    return result;
}
