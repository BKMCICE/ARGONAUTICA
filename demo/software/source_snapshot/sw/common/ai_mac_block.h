/* A01 explicit opt-in driver. Results are raw signed int32, without Q24/bias.
 * Input is CHW, weight rows are output-major. Caller owns these buffers and the
 * AI unit throughout a call. Supports a bounded row/tile within one input plane.
 */
#ifndef AI_MAC_BLOCK_H
#define AI_MAC_BLOCK_H
#include "soc.h"
#define AI_BLOCK_ID 0x41303131u
#define AI_BLOCK_REG_ID 0x100u
#define AI_BLOCK_CTRL 0x104u
#define AI_BLOCK_SHAPE 0x108u
#define AI_BLOCK_WADDR 0x10cu
#define AI_BLOCK_WDATA 0x110u
#define AI_BLOCK_PADDR 0x114u
#define AI_BLOCK_PDATA 0x118u
#define AI_BLOCK_RADDR 0x11cu
#define AI_BLOCK_RDATA 0x120u
#define AI_BLOCK_CYCLES 0x124u
#define AI_BLOCK_DOTS 0x128u
#ifndef AI_BLOCK_READ
#define AI_BLOCK_READ(off) REG32(AI_BASE+(off))
#define AI_BLOCK_WRITE(off,value) (REG32(AI_BASE+(off))=(value))
#endif
#define AI_BLOCK_OK 0
#define AI_BLOCK_UNSUPPORTED (-1)
#define AI_BLOCK_BAD_SHAPE (-2)
#define AI_BLOCK_HW_ERROR (-3)
#define AI_BLOCK_TIMEOUT (-4)
static inline int ai_run_1x1_block(const int8_t *input,uint32_t plane,
    uint32_t first_pixel,uint32_t stride,uint32_t channels,
    const int8_t *weights,uint32_t weight_stride,uint32_t pixels,uint32_t outputs,
    int32_t *result,uint32_t *engine_cycles)
{
    if(!input || !weights || !result || !channels || channels>224u || !pixels || pixels>8u ||
       !outputs || outputs>4u || !plane || !stride || first_pixel>=plane ||
       pixels-1u>(plane-1u-first_pixel)/stride || weight_stride<channels ||
       plane>UINT32_MAX/channels || (outputs>1u && weight_stride>(UINT32_MAX-channels)/(outputs-1u)))
        return AI_BLOCK_BAD_SHAPE;
    if(AI_BLOCK_READ(AI_BLOCK_REG_ID)!=AI_BLOCK_ID) return AI_BLOCK_UNSUPPORTED;
    if(AI_BLOCK_READ(AI_BLOCK_CTRL)&1u) return AI_BLOCK_HW_ERROR;
    uint32_t blocks=(channels+8u)/9u;
    AI_BLOCK_WRITE(AI_BLOCK_CTRL,4u);
    AI_BLOCK_WRITE(AI_BLOCK_WADDR,0);
    for(uint32_t oc=0;oc<outputs;++oc) for(uint32_t b=0;b<blocks;++b) {
        uint32_t packed[3];packed[0]=0;packed[1]=0;packed[2]=0;
        for(uint32_t lane=0;lane<9u && b*9u+lane<channels;++lane)
            packed[lane>>2]|=(uint32_t)(uint8_t)weights[oc*weight_stride+b*9u+lane]<<((lane&3u)*8u);
        for(uint32_t word=0;word<3;++word) AI_BLOCK_WRITE(AI_BLOCK_WDATA,packed[word]);
    }
    AI_BLOCK_WRITE(AI_BLOCK_PADDR,0);
    for(uint32_t b=0;b<blocks;++b) for(uint32_t p=0;p<pixels;++p) {
        uint32_t packed[3];packed[0]=0;packed[1]=0;packed[2]=0;
        for(uint32_t lane=0;lane<9u && b*9u+lane<channels;++lane)
            packed[lane>>2]|=(uint32_t)(uint8_t)input[(b*9u+lane)*plane+first_pixel+p*stride]<<((lane&3u)*8u);
        for(uint32_t word=0;word<3;++word) AI_BLOCK_WRITE(AI_BLOCK_PDATA,packed[word]);
    }
    AI_BLOCK_WRITE(AI_BLOCK_SHAPE,pixels|(outputs<<4)|(blocks<<8)|((channels-(blocks-1u)*9u)<<16));
    AI_BLOCK_WRITE(AI_BLOCK_CTRL,1u);
    uint32_t status=0,polls=0;
    do {status=AI_BLOCK_READ(AI_BLOCK_CTRL);++polls;} while(!(status&2u) && polls<100000u);
    if(!(status&2u)) return AI_BLOCK_TIMEOUT;
    if(status&5u) return AI_BLOCK_HW_ERROR;
    AI_BLOCK_WRITE(AI_BLOCK_RADDR,0);
    for(uint32_t i=0;i<outputs*pixels;++i) result[i]=(int32_t)AI_BLOCK_READ(AI_BLOCK_RDATA);
    if(AI_BLOCK_READ(AI_BLOCK_CTRL)&4u) return AI_BLOCK_HW_ERROR;
    if(engine_cycles) *engine_cycles=AI_BLOCK_READ(AI_BLOCK_CYCLES);
    return AI_BLOCK_OK;
}
#endif
