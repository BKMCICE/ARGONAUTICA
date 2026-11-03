/* The optional post8 build keeps its legacy raw readback in cached DDR.
 * Both paths share validation, cache packing, upload and submission in main.c.
 * Only successful tasks reach this helper; readback errors never trigger retry.
 * .ddr_rgb3 is the existing cold-code output region, after hot TCM text. */
#ifndef YOLO_BLOCK_POST8_H
#define YOLO_BLOCK_POST8_H
__attribute__((noinline, section(".ddr_rgb3")))
static int block_post8_raw_store(int8_t *dest, uint32_t plane,
    const int32_t *params, uint32_t pixels, uint32_t outputs, uint32_t leaky)
{
    int32_t acc[64];
    AI_BLOCK_WRITE(AI_BLOCK_RADDR, 0u);
    for (uint32_t i = 0; i < outputs * pixels; ++i)
        acc[i] = (int32_t)AI_BLOCK_READ(AI_BLOCK_RDATA);
    if (AI_BLOCK_READ(AI_BLOCK_CTRL) & 4u) return AI_BLOCK_HW_ERROR;
    for (uint32_t ch = 0; ch < outputs; ++ch)
        block_q24_store(acc + ch * pixels, dest + ch * plane,
            pixels, params[ch * 2], params[ch * 2 + 1], leaky);
    return AI_BLOCK_OK;
}
#endif
