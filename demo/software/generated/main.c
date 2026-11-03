/* Fixed-point YOLO-Fastest layer executor for RV32IM + cached DDR.
 * The model/data/expected head hashes come from tools/yolo_emit_rv32.py.
 */
#include "soc.h"
#include "result_ui.h"
#include "ai_mac.h"
#ifndef YOLO_IDENTITY_FORWARD
#define YOLO_IDENTITY_FORWARD 0
#endif
#if YOLO_IDENTITY_FORWARD != 0 && YOLO_IDENTITY_FORWARD != 1
#error "YOLO_IDENTITY_FORWARD supports only 0 or 1"
#endif
#if YOLO_IDENTITY_FORWARD && (!YOLO_REUSE_ACTIVATIONS || !YOLO_1X1_ACC32)
#error "YOLO_IDENTITY_FORWARD requires compact activations and safe convolution error propagation"
#endif
#ifndef YOLO_IDENTITY_FASTPATH
#define YOLO_IDENTITY_FASTPATH 0
#endif
#if YOLO_IDENTITY_FASTPATH != 0 && YOLO_IDENTITY_FASTPATH != 1
#error "YOLO_IDENTITY_FASTPATH supports only 0 or 1"
#endif
#ifndef YOLO_SHORTCUT_LUT
#define YOLO_SHORTCUT_LUT 0
#endif
#if YOLO_SHORTCUT_LUT != 0 && YOLO_SHORTCUT_LUT != 1
#error "YOLO_SHORTCUT_LUT supports only 0 or 1"
#endif
#ifndef YOLO_DW3X3_ROLLING
#define YOLO_DW3X3_ROLLING 0
#endif
#ifndef YOLO_POOL_SEPARABLE
#define YOLO_POOL_SEPARABLE 0
#endif
#if YOLO_POOL_SEPARABLE != 0 && YOLO_POOL_SEPARABLE != 1
#error "YOLO_POOL_SEPARABLE supports only 0 or 1"
#endif
#ifndef YOLO_DW3_LEAKY_CLIP
#define YOLO_DW3_LEAKY_CLIP 0
#endif
#if YOLO_DW3_LEAKY_CLIP != 0 && YOLO_DW3_LEAKY_CLIP != 1
#error "YOLO_DW3_LEAKY_CLIP supports only 0 or 1"
#endif
#if YOLO_DW3_LEAKY_CLIP && !YOLO_DW3X3_ROLLING
#error "YOLO_DW3_LEAKY_CLIP requires YOLO_DW3X3_ROLLING=1"
#endif
#if YOLO_DW3X3_ROLLING != 0 && YOLO_DW3X3_ROLLING != 1
#error "YOLO_DW3X3_ROLLING supports only 0 or 1"
#endif
#if YOLO_DW3X3_ROLLING && (!YOLO_REUSE_DW3X3_WEIGHTS || !YOLO_1X1_ACC32)
#error "YOLO_DW3X3_ROLLING requires YOLO_REUSE_DW3X3_WEIGHTS=1 and YOLO_1X1_ACC32=1"
#endif
#ifndef YOLO_DW5X5_BLOCK
#define YOLO_DW5X5_BLOCK 0
#endif
#if YOLO_DW5X5_BLOCK != 0 && YOLO_DW5X5_BLOCK != 1
#error "YOLO_DW5X5_BLOCK supports only 0 or 1"
#endif
#if YOLO_DW5X5_BLOCK && !YOLO_1X1_ACC32
#error "YOLO_DW5X5_BLOCK requires YOLO_1X1_ACC32=1 for error propagation"
#endif
#ifndef YOLO_DW5_POST8
#define YOLO_DW5_POST8 0
#endif
#if YOLO_DW5_POST8 != 0 && YOLO_DW5_POST8 != 1
#error "YOLO_DW5_POST8 supports only 0 or 1"
#endif
#if YOLO_DW5_POST8 && (!YOLO_DW5X5_BLOCK || !YOLO_BLOCK_POST8 || !YOLO_1X1_ACC32)
#error "YOLO_DW5_POST8 requires DW5X5_BLOCK, BLOCK_POST8 and safe int32 accumulation"
#endif
#ifndef YOLO_DW5_PACK_FAST
#define YOLO_DW5_PACK_FAST 0
#endif
#if YOLO_DW5_PACK_FAST != 0 && YOLO_DW5_PACK_FAST != 1
#error "YOLO_DW5_PACK_FAST supports only 0 or 1"
#endif
#if YOLO_DW5_PACK_FAST && (!YOLO_DW5X5_BLOCK || !YOLO_DW5_POST8)
#error "YOLO_DW5_PACK_FAST requires YOLO_DW5X5_BLOCK=1 and YOLO_DW5_POST8=1"
#endif
#ifndef YOLO_1X1_BLOCK
#define YOLO_1X1_BLOCK 0
#endif
#if YOLO_1X1_BLOCK != 0 && YOLO_1X1_BLOCK != 1
#error "YOLO_1X1_BLOCK supports only 0 or 1"
#endif
#if YOLO_1X1_BLOCK && (!YOLO_1X1_ACC32 || !YOLO_REUSE_1X1_INPUT)
#error "YOLO_1X1_BLOCK requires YOLO_1X1_ACC32=1 and YOLO_REUSE_1X1_INPUT=1"
#endif
#if YOLO_1X1_BLOCK
#include "ai_mac_block.h"
#endif
#ifndef YOLO_BLOCK8
#define YOLO_BLOCK8 0
#endif
#if YOLO_BLOCK8 != 0 && YOLO_BLOCK8 != 1
#error "YOLO_BLOCK8 supports only 0 or 1"
#endif
#if YOLO_BLOCK8 && !YOLO_1X1_BLOCK
#error "YOLO_BLOCK8 requires YOLO_1X1_BLOCK=1"
#endif
#ifndef YOLO_BLOCK_POST8
#define YOLO_BLOCK_POST8 0
#endif
#if YOLO_BLOCK_POST8 != 0 && YOLO_BLOCK_POST8 != 1
#error "YOLO_BLOCK_POST8 supports only 0 or 1"
#endif
#if YOLO_BLOCK_POST8 && (!YOLO_BLOCK8 || !YOLO_1X1_BLOCK || !YOLO_1X1_ACC32)
#error "YOLO_BLOCK_POST8 requires block8, block1 and safe int32 accumulation"
#endif
#ifndef YOLO_POST8_WORD_STORE
#define YOLO_POST8_WORD_STORE 0
#endif
#if YOLO_POST8_WORD_STORE != 0 && YOLO_POST8_WORD_STORE != 1
#error "YOLO_POST8_WORD_STORE supports only 0 or 1"
#endif
#if YOLO_POST8_WORD_STORE && !YOLO_BLOCK_POST8
#error "YOLO_POST8_WORD_STORE requires YOLO_BLOCK_POST8=1"
#endif
#if YOLO_POST8_WORD_STORE
#include "post8_word_store.h"
#endif
#ifndef YOLO_RGB3_BLOCK
#define YOLO_RGB3_BLOCK 0
#endif
#if YOLO_RGB3_BLOCK != 0 && YOLO_RGB3_BLOCK != 1
#error "YOLO_RGB3_BLOCK supports only 0 or 1"
#endif
#if YOLO_RGB3_BLOCK && (!YOLO_3X3_INPUT3_PREPACK || !YOLO_1X1_ACC32)
#error "YOLO_RGB3_BLOCK requires YOLO_3X3_INPUT3_PREPACK=1 and YOLO_1X1_ACC32=1"
#endif
#ifndef YOLO_BLOCK_Q24_REUSE
#define YOLO_BLOCK_Q24_REUSE 0
#endif
#if YOLO_BLOCK_Q24_REUSE != 0 && YOLO_BLOCK_Q24_REUSE != 1
#error "YOLO_BLOCK_Q24_REUSE supports only 0 or 1"
#endif
#if YOLO_BLOCK_Q24_REUSE && !YOLO_1X1_BLOCK
#error "YOLO_BLOCK_Q24_REUSE requires YOLO_1X1_BLOCK=1"
#endif
#ifndef YOLO_BLOCK_PHASE_PROFILE
#define YOLO_BLOCK_PHASE_PROFILE 0
#endif
#if YOLO_BLOCK_PHASE_PROFILE != 0 && YOLO_BLOCK_PHASE_PROFILE != 1
#error "YOLO_BLOCK_PHASE_PROFILE supports only 0 or 1"
#endif
#if YOLO_BLOCK_PHASE_PROFILE && (!YOLO_1X1_BLOCK || !YOLO_LAYER_PROFILE || defined(YOLO_HOST_TEST))
#error "YOLO_BLOCK_PHASE_PROFILE requires target YOLO_1X1_BLOCK=1 and YOLO_LAYER_PROFILE=1"
#endif
#ifndef YOLO_BLOCK_CACHE_PHASE_PROFILE
#define YOLO_BLOCK_CACHE_PHASE_PROFILE 0
#endif
#if YOLO_BLOCK_CACHE_PHASE_PROFILE != 0 && YOLO_BLOCK_CACHE_PHASE_PROFILE != 1
#error "YOLO_BLOCK_CACHE_PHASE_PROFILE supports only 0 or 1"
#endif
#if YOLO_BLOCK_CACHE_PHASE_PROFILE && (!YOLO_BLOCK_PHASE_PROFILE || !YOLO_BLOCK_INPUT_CACHE)
#error "YOLO_BLOCK_CACHE_PHASE_PROFILE requires phase profiling and input cache"
#endif
#ifndef YOLO_BLOCK_INPUT_CACHE
#define YOLO_BLOCK_INPUT_CACHE 0
#endif
#if YOLO_BLOCK_INPUT_CACHE != 0 && YOLO_BLOCK_INPUT_CACHE != 1
#error "YOLO_BLOCK_INPUT_CACHE supports only 0 or 1"
#endif
#if YOLO_BLOCK_INPUT_CACHE && (!YOLO_1X1_BLOCK || (YOLO_BLOCK_PHASE_PROFILE && !YOLO_BLOCK_CACHE_PHASE_PROFILE))
#error "YOLO_BLOCK_INPUT_CACHE requires block1; phase sampling additionally requires YOLO_BLOCK_CACHE_PHASE_PROFILE=1"
#endif
#ifndef YOLO_CACHE_PACK4
#define YOLO_CACHE_PACK4 0
#endif
#if YOLO_CACHE_PACK4 != 0 && YOLO_CACHE_PACK4 != 1
#error "YOLO_CACHE_PACK4 supports only 0 or 1"
#endif
#if YOLO_CACHE_PACK4 && (!YOLO_BLOCK_INPUT_CACHE || !YOLO_1X1_BLOCK)
#error "YOLO_CACHE_PACK4 requires YOLO_BLOCK_INPUT_CACHE=1 and YOLO_1X1_BLOCK=1"
#endif
#ifndef YOLO_3X3_INPUT3_PREPACK
#define YOLO_3X3_INPUT3_PREPACK 0
#endif
#if YOLO_3X3_INPUT3_PREPACK != 0 && YOLO_3X3_INPUT3_PREPACK != 1
#error "YOLO_3X3_INPUT3_PREPACK supports only 0 or 1"
#endif
#if YOLO_3X3_INPUT3_PREPACK && (!YOLO_REUSE_DW3X3_WEIGHTS || !YOLO_TILE_1X1_WEIGHTS)
#error "YOLO_3X3_INPUT3_PREPACK requires YOLO_REUSE_DW3X3_WEIGHTS=1 and YOLO_TILE_1X1_WEIGHTS=1"
#endif
#ifndef YOLO_1X1_SMALL_PACK
#define YOLO_1X1_SMALL_PACK 0
#endif
#if YOLO_1X1_SMALL_PACK != 0 && YOLO_1X1_SMALL_PACK != 1
#error "YOLO_1X1_SMALL_PACK supports only 0 or 1"
#endif
#if YOLO_1X1_SMALL_PACK && !YOLO_REUSE_1X1_WEIGHTS
#error "YOLO_1X1_SMALL_PACK requires YOLO_REUSE_1X1_WEIGHTS=1"
#endif
#ifndef YOLO_1X1_PACK9
#define YOLO_1X1_PACK9 0
#endif
#if YOLO_1X1_PACK9 != 0 && YOLO_1X1_PACK9 != 1
#error "YOLO_1X1_PACK9 supports only 0 or 1"
#endif
#if YOLO_1X1_PACK9 && !YOLO_REUSE_1X1_INPUT
#error "YOLO_1X1_PACK9 requires YOLO_REUSE_1X1_INPUT=1"
#endif
#ifndef YOLO_DW3X3_INTERIOR
#define YOLO_DW3X3_INTERIOR 0
#endif
#if YOLO_DW3X3_INTERIOR != 0 && YOLO_DW3X3_INTERIOR != 1
#error "YOLO_DW3X3_INTERIOR supports only 0 or 1"
#endif
#if YOLO_DW3X3_INTERIOR && !YOLO_REUSE_DW3X3_WEIGHTS
#error "YOLO_DW3X3_INTERIOR requires YOLO_REUSE_DW3X3_WEIGHTS=1"
#endif
#ifndef YOLO_1X1_ACC32
#define YOLO_1X1_ACC32 0
#endif
#if YOLO_1X1_ACC32 != 0 && YOLO_1X1_ACC32 != 1
#error "YOLO_1X1_ACC32 supports only 0 or 1"
#endif
#if YOLO_1X1_ACC32 && !YOLO_REUSE_1X1_INPUT
#error "YOLO_1X1_ACC32 requires YOLO_REUSE_1X1_INPUT=1"
#endif
#ifndef YOLO_1X1_INPUT_BATCH
#define YOLO_1X1_INPUT_BATCH 4
#endif
#if YOLO_1X1_INPUT_BATCH == 12 && !YOLO_REUSE_1X1_INPUT
#error "YOLO_1X1_INPUT_BATCH=12 requires YOLO_REUSE_1X1_INPUT=1"
#endif
#if YOLO_1X1_INPUT_BATCH != 4 && YOLO_1X1_INPUT_BATCH != 8 && YOLO_1X1_INPUT_BATCH != 12
#error "YOLO_1X1_INPUT_BATCH supports only 4, 8 or 12 output channels"
#endif
#if YOLO_REUSE_1X1_INPUT
#include "ai_mac_input_tile.h"
#endif
#if YOLO_TILE_1X1_WEIGHTS
#include "ai_mac_tile.h"
#endif
#include "model_graph.h"
#if YOLO_BLOCK_PHASE_PROFILE
#include "block_profile.h"
#endif
#if YOLO_REUSE_DW3X3_WEIGHTS
#include "ai_mac_dw3x3.h"
#endif
#if YOLO_TCM_LAYER
#include "layer_cache.h"
#endif
#if YOLO_REUSE_1X1_WEIGHTS
#include "ai_mac_reuse.h"
#endif
#if YOLO_PREPACK_1X1_WEIGHTS
#include "ai_mac_prepack.h"
#endif

#if YOLO_REUSE_ACTIVATIONS
#if YOLO_IDENTITY_FORWARD
#include "model_identity_arena.h"
#else
#include "model_arena.h"
#endif
static int8_t arena[YOLO_COMPACT_ACTIVATION_BYTES] __attribute__((aligned(32)));
#else
static int8_t arena[YOLO_ACTIVATION_BYTES];
#endif
void yolo_print_detections(const int8_t *head0, const int8_t *head1);

#if YOLO_LAYER_PROFILE
#ifdef YOLO_HOST_TEST
#error "YOLO_LAYER_PROFILE requires the target mcycle CSR"
#endif
static uint64_t layer_cycles[YOLO_LAYER_COUNT];

/* Keep memory accesses within the sampled operator window. */
static inline uint64_t layer_clock(void)
{
    __asm__ volatile("" ::: "memory");
    uint64_t value = rdcycle64();
    __asm__ volatile("" ::: "memory");
    return value;
}

#if YOLO_RGB3_BLOCK && TCM_TEXT && TCM_STACK
/* Post-inference diagnostics share the cold DDR section with RGB fallback.
 * This declaration is absent when profiling is off; preserve the fixed
 * TCM code/stack split instead of consuming stack for diagnostic text. */
__attribute__((noinline,section(".ddr_rgb3")))
#endif
static void print_layer_profile(void)
{
    uart_puts("YOLO_PROFILE_BEGIN layers=");
    uart_putdec(YOLO_LAYER_COUNT); uart_putc('\n');
    for (uint32_t i = 0; i < YOLO_LAYER_COUNT; ++i) {
        uart_puts("YOLO_LAYER index="); uart_putdec(i);
        uart_puts(" kind="); uart_putdec(yolo_layers[i].kind);
        uart_puts(" kernel="); uart_putdec(yolo_layers[i].size);
        uart_puts(" cycles=0x");
        uart_puthex((uint32_t)(layer_cycles[i] >> 32));
        uart_puthex((uint32_t)layer_cycles[i]); uart_putc('\n');
    }
    uart_puts("YOLO_PROFILE_END\n");
}
#endif

#if YOLO_UART_IMAGE
uint32_t h07_chw_guard_low[8] __attribute__((section(".h07_chw_guard_low"),aligned(32)));
int8_t uart_image[YOLO_INPUT_BYTES] __attribute__((section(".h07_chw"),aligned(32)));
uint32_t h07_chw_guard_high[8] __attribute__((section(".h07_chw_guard_high"),aligned(32)));
extern int h07_capture_to_chw(int8_t *,uint32_t);
extern int h07_finish_input(void);
extern int h07_yolo_failure(uint32_t);
static int receive_image(void) { return h07_capture_to_chw(uart_image,YOLO_INPUT_BYTES); }
#else
#error "H07 requires production YOLO_UART_IMAGE input semantics"
#endif

static int32_t apply_q24(int64_t value, int32_t multiplier)
{
    int64_t product = value * multiplier;
    if (product >= 0) return (int32_t)((product + (1LL << 23)) >> 24);
    return -(int32_t)(((-product) + (1LL << 23)) >> 24);
}

static int8_t clip8(int32_t value)
{
    if (value > 127) return 127;
    if (value < -127) return -127;
    return (int8_t)value;
}

#if YOLO_SHORTCUT_LUT
#include "int8_shortcut_lut.h"
/* Dedicated DDR object: never shares storage with live activations or the
 * convolution input cache. Inference executes one layer at a time; no ISR
 * calls this operator. Each invocation rebuilds both tables before use. */
static Int8ShortcutLut shortcut_lut_scratch __attribute__((aligned(32)));
#endif

#if YOLO_RGB3_BLOCK
#include "rgb3_block.h"
#endif

#if YOLO_BLOCK_Q24_REUSE || YOLO_BLOCK_POST8
#include "block_q24_reuse.h"
#endif
#if YOLO_BLOCK_POST8
#include "block_post8.h"
#endif

#if YOLO_DW3X3_ROLLING
#include "dw3x3_rolling.h"
#endif
#if YOLO_DW5X5_BLOCK
#include "dw5x5_block.h"
#endif
#if YOLO_BLOCK_INPUT_CACHE
#include "block_input_cache.h"
#endif
#if YOLO_1X1_BLOCK
/* Own the AI unit for this whole operator. ACK retains loaded weights. Each
 * output batch loads its weights once, then visits eight spatial pixels.
 * No DMA: packing and MMIO run on the CPU; optional A481 offloads final Q24.
 * Only UNSUPPORTED/BAD_SHAPE before writes may fall back to a legacy operator;
 * a busy/error/timeout or bad readback must propagate as an inference failure. */
__attribute__((noinline)) static int conv1x1_block(const YoloLayer *layer,
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
#if YOLO_POST8_WORD_STORE
                                post8_word_store(dest + p, word, count);
                                p += count;
#else
                                for (uint32_t byte = 0; byte < count; ++byte) {
                                    dest[p++] = (int8_t)word;
                                    word >>= 8;
                                }
#endif
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
#endif

static const int8_t *output_of(int index)
{
#if YOLO_REUSE_ACTIVATIONS
    return arena + yolo_compact_offsets[index];
#else
    return arena + yolo_layers[index].output_offset;
#endif
}

#if YOLO_REUSE_1X1_WEIGHTS
/* Keep the specialized loop separate from the generic convolution executor. */
__attribute__((noinline)) static void conv1x1_small(const YoloLayer *layer,
    const int8_t *input, int8_t *output, const int8_t *kernels,
    const int32_t *params, uint32_t in_group, uint32_t out_group)
{
    uint32_t plane = layer->ih * layer->iw;
    for (uint32_t oc = 0; oc < layer->oc; ++oc) {
        uint32_t in_base = (oc / out_group) * in_group;
        const int8_t *group_input = input + in_base * plane;
        ai_load_1x1_weights(kernels + oc * in_group, in_group);
        for (uint32_t oy = 0; oy < layer->oh; ++oy) {
            for (uint32_t ox = 0; ox < layer->ow; ++ox) {
                uint32_t pixel = oy * layer->stride * layer->iw + ox * layer->stride;
                int32_t acc = ai_dot1x1_loaded(group_input, plane, pixel, in_group);
                int32_t value = apply_q24(acc, params[oc * 2]) + params[oc * 2 + 1];
                if (layer->leaky && value < 0) value = apply_q24(value, YOLO_LEAKY_Q24);
                output[(oc * layer->oh + oy) * layer->ow + ox] = clip8(value);
            }
        }
    }
}
#endif

#if YOLO_PREPACK_1X1_WEIGHTS && !YOLO_TILE_1X1_WEIGHTS
__attribute__((noinline)) static void conv1x1_prepacked(const YoloLayer *layer,
    const int8_t *input, int8_t *output, const int8_t *kernels,
    const int32_t *params, uint32_t in_group, uint32_t out_group)
{
    uint32_t blocks = (in_group + 8) / 9;
    /* Current model: at most 25 blocks, 300 bytes, reused for each output channel. */
    uint32_t packed[blocks * 3];
    uint32_t plane = layer->ih * layer->iw;
    for (uint32_t oc = 0; oc < layer->oc; ++oc) {
        for (uint32_t block = 0; block < blocks; ++block) {
            uint32_t first = block * 9;
            uint32_t count = in_group - first;
            if (count > 9) count = 9;
            ai_pack_1x1_weights(kernels + oc * in_group + first, count, packed + block * 3);
        }
        uint32_t in_base = (oc / out_group) * in_group;
        for (uint32_t oy = 0; oy < layer->oh; ++oy) {
            for (uint32_t ox = 0; ox < layer->ow; ++ox) {
                uint32_t pixel = oy * layer->stride * layer->iw + ox * layer->stride;
                int64_t acc = 0;
                for (uint32_t block = 0; block < blocks; ++block) {
                    uint32_t first = block * 9;
                    uint32_t count = in_group - first;
                    if (count > 9) count = 9;
                    acc += ai_dot1x1_prepacked(input + (in_base + first) * plane,
                                              plane, pixel, count, packed + block * 3);
                }
                int32_t value = apply_q24(acc, params[oc * 2]) + params[oc * 2 + 1];
                if (layer->leaky && value < 0) value = apply_q24(value, YOLO_LEAKY_Q24);
                output[(oc * layer->oh + oy) * layer->ow + ox] = clip8(value);
            }
        }
    }
}
#endif

#if YOLO_TILE_1X1_WEIGHTS && !YOLO_REUSE_1X1_INPUT
__attribute__((noinline)) static void conv1x1_tiled(const YoloLayer *layer,
    const int8_t *input, int8_t *output, const int8_t *kernels,
    const int32_t *params, uint32_t in_group, uint32_t out_group)
{
    uint32_t blocks = (in_group + 8) / 9;
    /* The generated model bounds this VLA to 300B (304B after alignment). */
    uint32_t packed[blocks * 3];
    uint32_t plane = layer->ih * layer->iw;
    for (uint32_t oc = 0; oc < layer->oc; ++oc) {
        for (uint32_t block = 0; block < blocks; ++block) {
            uint32_t first = block * 9;
            uint32_t count = in_group - first;
            if (count > 9) count = 9;
            ai_pack_1x1_weights(kernels + oc * in_group + first, count, packed + block * 3);
        }
        uint32_t in_base = (oc / out_group) * in_group;
        for (uint32_t oy = 0; oy < layer->oh; ++oy) {
            for (uint32_t ox = 0; ox < layer->ow; ox += 8) {
                uint32_t count_pixels = layer->ow - ox;
                if (count_pixels > 8) count_pixels = 8;
                /* Volatile stores avoid an implicit libc memset in freestanding builds. */
                volatile int64_t acc[8];
                for (uint32_t lane = 0; lane < count_pixels; ++lane) acc[lane] = 0;
                uint32_t pixel = oy * layer->stride * layer->iw + ox * layer->stride;
                for (uint32_t block = 0; block < blocks; ++block) {
                    uint32_t first = block * 9;
                    uint32_t count = in_group - first;
                    if (count > 9) count = 9;
                    ai_load_prepacked_weights(packed + block * 3);
                    for (uint32_t lane = 0; lane < count_pixels; ++lane)
                        acc[lane] += ai_dot1x1_loaded(input + (in_base + first) * plane,
                            plane, pixel + lane * layer->stride, count);
                }
                for (uint32_t lane = 0; lane < count_pixels; ++lane) {
                    int32_t value = apply_q24(acc[lane], params[oc * 2]) + params[oc * 2 + 1];
                    if (layer->leaky && value < 0) value = apply_q24(value, YOLO_LEAKY_Q24);
                    output[(oc * layer->oh + oy) * layer->ow + ox + lane] = clip8(value);
                }
            }
        }
    }
}
#endif

#if YOLO_REUSE_1X1_INPUT
#if YOLO_1X1_ACC32
__attribute__((noinline)) static int conv1x1_input_reuse(const YoloLayer *layer,
#else
__attribute__((noinline)) static void conv1x1_input_reuse(const YoloLayer *layer,
#endif
    const int8_t *input, int8_t *output, const int8_t *kernels,
    const int32_t *params, uint32_t in_group, uint32_t out_group)
{
#if YOLO_1X1_ACC32
    /* Closed-model bound also limits the VLA to the audited 25 blocks.
     * AI_BIAS must remain zero and this call must own the AI registers.
     * Raw INT8 sum: [-16256,16384]*224 fits int32_t; Q24 stays int64_t.
     * Reject before touching pointers or allocating the scratch frame. */
    if (in_group > 224u) return 0;
#endif
    uint32_t blocks = (in_group + 8) / 9;
    /* Current graph: <=25 blocks. B weight sets + eight pixel sets:
     * B=4 uses 3600B; B=8 uses 4800B; B=12 uses 6000B.
     * One VLA makes its aligned stack bound independently auditable. */
    uint32_t scratch[blocks * (3 * YOLO_1X1_INPUT_BATCH + 24)];
    uint32_t *packed_input = scratch + blocks * (3 * YOLO_1X1_INPUT_BATCH);
    uint32_t plane = layer->ih * layer->iw;
    for (uint32_t group = 0; group < layer->groups; ++group) {
        const int8_t *group_input = input + group * in_group * plane;
        for (uint32_t oc_base = 0; oc_base < out_group; oc_base += YOLO_1X1_INPUT_BATCH) {
            uint32_t outputs = out_group - oc_base;
            if (outputs > YOLO_1X1_INPUT_BATCH) outputs = YOLO_1X1_INPUT_BATCH;
            for (uint32_t ch = 0; ch < outputs; ++ch) {
                uint32_t oc = group * out_group + oc_base + ch;
                for (uint32_t block = 0; block < blocks; ++block) {
                    uint32_t first = block * 9, count = in_group - first;
                    if (count > 9) count = 9;
                    ai_pack_1x1_weights(kernels + oc * in_group + first, count,
                                       scratch + (ch * blocks + block) * 3);
                }
            }
            for (uint32_t oy = 0; oy < layer->oh; ++oy) {
                for (uint32_t ox = 0; ox < layer->ow; ox += 8) {
                    uint32_t pixels = layer->ow - ox;
                    if (pixels > 8) pixels = 8;
                    uint32_t pixel = oy * layer->stride * layer->iw + ox * layer->stride;
                    for (uint32_t block = 0; block < blocks; ++block) {
                        uint32_t first = block * 9, count = in_group - first;
                        if (count > 9) count = 9;
                        for (uint32_t lane = 0; lane < pixels; ++lane)
                            ai_pack_1x1_input(group_input + first * plane, plane,
                                pixel + lane * layer->stride, count,
                                packed_input + (block * 8 + lane) * 3);
                    }
                    for (uint32_t ch = 0; ch < outputs; ++ch) {
                        uint32_t oc = group * out_group + oc_base + ch;
                        /* Process output channels sequentially: only eight accumulators. */
#if YOLO_1X1_ACC32
                        volatile int32_t acc[8];
#else
                        volatile int64_t acc[8];
#endif
                        for (uint32_t lane = 0; lane < pixels; ++lane) acc[lane] = 0;
                        for (uint32_t block = 0; block < blocks; ++block) {
                            ai_load_prepacked_weights(scratch + (ch * blocks + block) * 3);
                            for (uint32_t lane = 0; lane < pixels; ++lane)
                                acc[lane] += ai_dot_prepacked_loaded(packed_input + (block * 8 + lane) * 3);
                        }
                        for (uint32_t lane = 0; lane < pixels; ++lane) {
                            int32_t value = apply_q24(acc[lane], params[oc * 2]) + params[oc * 2 + 1];
                            if (layer->leaky && value < 0) value = apply_q24(value, YOLO_LEAKY_Q24);
                            output[(oc * layer->oh + oy) * layer->ow + ox + lane] = clip8(value);
                        }
                    }
                }
            }
        }
    }
#if YOLO_1X1_ACC32
    return 1;
#endif
}
#endif

#if YOLO_REUSE_DW3X3_WEIGHTS
__attribute__((noinline)) static void conv3x3_depthwise_reuse(const YoloLayer *layer,
    const int8_t *input, int8_t *output, const int8_t *kernels, const int32_t *params)
{
    uint32_t plane = layer->ih * layer->iw;
    for (uint32_t oc = 0; oc < layer->oc; ++oc) {
        const int8_t *channel_input = input + oc * plane;
        /* Lane order is the same row-major order as the original ai_dot3x3. */
        ai_load_1x1_weights(kernels + oc * 9, 9);
        for (uint32_t oy = 0; oy < layer->oh; ++oy) {
            for (uint32_t ox = 0; ox < layer->ow; ++ox) {
                int32_t acc = ai_dot3x3_loaded(channel_input, layer->ih, layer->iw,
                    (int32_t)(oy * layer->stride) - (int32_t)layer->pad,
                    (int32_t)(ox * layer->stride) - (int32_t)layer->pad);
                int32_t value = apply_q24(acc, params[oc * 2]) + params[oc * 2 + 1];
                if (layer->leaky && value < 0) value = apply_q24(value, YOLO_LEAKY_Q24);
                output[(oc * layer->oh + oy) * layer->ow + ox] = clip8(value);
            }
        }
    }
}
#endif

#if YOLO_3X3_INPUT3_PREPACK
/* Caller selects size=3, in_group=3. Keep channel sums unquantized. */
#if YOLO_RGB3_BLOCK && TCM_TEXT && TCM_STACK && !defined(YOLO_HOST_TEST)
/* Cold RGB fallback stays executable from cached DDR; hot block code and
 * all other operators retain the existing fixed TCM/stack split. */
__attribute__((noinline,section(".ddr_rgb3")))
#else
__attribute__((noinline))
#endif
static void conv3x3_input3_prepacked(const YoloLayer *layer,
    const int8_t *input, int8_t *output, const int8_t *kernels,
    const int32_t *params, uint32_t out_group)
{
    uint32_t packed[9];
    uint32_t plane = layer->ih * layer->iw;
    for (uint32_t oc = 0; oc < layer->oc; ++oc) {
        const int8_t *group_input = input + (oc / out_group) * 3u * plane;
        for (uint32_t ic = 0; ic < 3; ++ic)
            ai_pack_1x1_weights(kernels + (oc * 3u + ic) * 9u, 9, packed + ic * 3u);
        for (uint32_t oy = 0; oy < layer->oh; ++oy) {
            for (uint32_t ox = 0; ox < layer->ow; ++ox) {
                int64_t acc = 0;
                for (uint32_t ic = 0; ic < 3; ++ic) {
                    ai_load_prepacked_weights(packed + ic * 3u);
                    acc += ai_dot3x3_loaded(group_input + ic * plane,
                        layer->ih, layer->iw,
                        (int32_t)(oy * layer->stride) - (int32_t)layer->pad,
                        (int32_t)(ox * layer->stride) - (int32_t)layer->pad);
                }
                int32_t value = apply_q24(acc, params[oc * 2]) + params[oc * 2 + 1];
                if (layer->leaky && value < 0) value = apply_q24(value, YOLO_LEAKY_Q24);
                output[(oc * layer->oh + oy) * layer->ow + ox] = clip8(value);
            }
        }
    }
}
#endif

#if YOLO_1X1_ACC32
static int conv_layer(const YoloLayer *layer, const int8_t *input, int8_t *output)
#else
static void conv_layer(const YoloLayer *layer, const int8_t *input, int8_t *output)
#endif
{
    uint32_t in_group = layer->ic / layer->groups;
    uint32_t out_group = layer->oc / layer->groups;
    const int8_t *kernels = yolo_weights + layer->weight_offset;
    const int32_t *params = yolo_params_q24 + layer->param_offset / 4;
#if YOLO_DW5X5_BLOCK
    if (layer->size == 5 && in_group == 1 && out_group == 1) {
        int result = conv5x5_block(layer, input, output, kernels, params);
        if (result == AI_BLOCK_OK) return 1;
        if (result != AI_BLOCK_UNSUPPORTED && result != AI_BLOCK_BAD_SHAPE) return 0;
    }
#endif
#if YOLO_1X1_BLOCK
    if (layer->size == 1) {
        int result = conv1x1_block(layer, input, output, kernels, params, in_group, out_group);
        if (result == AI_BLOCK_OK) return 1;
        if (result != AI_BLOCK_UNSUPPORTED && result != AI_BLOCK_BAD_SHAPE) return 0;
    }
#endif
#if YOLO_RGB3_BLOCK
    /* Only ordinary RGB convolution; the measured single-pixel case stays
     * on the existing path. Unsupported ID is detected before any write.
     * Other errors may follow partial output and must stop this inference. */
    if (layer->size == 3 && layer->ic == 3 && layer->groups == 1 &&
        (layer->oh > 1 || layer->ow > 1)) {
        int result = rgb3_block(layer, input, output, kernels, params);
        if (result == AI_BLOCK_OK) return 1;
        if (result != AI_BLOCK_UNSUPPORTED) return 0;
    }
#endif
#if YOLO_3X3_INPUT3_PREPACK
    if (layer->size == 3 && in_group == 3) {
        conv3x3_input3_prepacked(layer, input, output, kernels, params, out_group);
#if YOLO_1X1_ACC32
        return 1;
#else
        return;
#endif
    }
#endif
#if YOLO_REUSE_DW3X3_WEIGHTS
    if (layer->size == 3 && in_group == 1 && out_group == 1) {
#if YOLO_DW3X3_ROLLING
        int result = conv3x3_rolling(layer, input, output, kernels, params);
        if (result == AI_BLOCK_OK) return 1;
        if (result != AI_BLOCK_BAD_SHAPE) return 0;
#endif
        conv3x3_depthwise_reuse(layer, input, output, kernels, params);
#if YOLO_1X1_ACC32
        return 1;
#else
        return;
#endif
    }
#endif
#if YOLO_PREPACK_1X1_WEIGHTS
    if (layer->size == 1 && in_group > 9) {
#if YOLO_REUSE_1X1_INPUT
#if YOLO_1X1_ACC32
        return conv1x1_input_reuse(layer, input, output, kernels, params, in_group, out_group);
#else
        conv1x1_input_reuse(layer, input, output, kernels, params, in_group, out_group);
#endif
#elif YOLO_TILE_1X1_WEIGHTS
        conv1x1_tiled(layer, input, output, kernels, params, in_group, out_group);
#else
        conv1x1_prepacked(layer, input, output, kernels, params, in_group, out_group);
#endif
#if YOLO_1X1_ACC32
        return 1;
#else
        return;
#endif
    }
#endif
#if YOLO_REUSE_1X1_WEIGHTS
    if (layer->size == 1 && in_group <= 9) {
        conv1x1_small(layer, input, output, kernels, params, in_group, out_group);
#if YOLO_1X1_ACC32
        return 1;
#else
        return;
#endif
    }
#endif
    for (uint32_t oc = 0; oc < layer->oc; ++oc) {
        uint32_t in_base = (oc / out_group) * in_group;
        for (uint32_t oy = 0; oy < layer->oh; ++oy) {
            for (uint32_t ox = 0; ox < layer->ow; ++ox) {
                int64_t acc = 0;
                for (uint32_t ic = 0; ic < in_group; ++ic) {
                    if (layer->size == 1) {
                        uint32_t batch = in_group - ic;
                        if (batch > 9) batch = 9;
                        uint32_t plane = layer->ih * layer->iw;
                        uint32_t pixel = oy * layer->stride * layer->iw + ox * layer->stride;
                        acc += ai_dot1x1(input + (in_base + ic) * plane,
                                         kernels + oc * in_group + ic,
                                         plane, pixel, batch);
                        ic += batch - 1;
                        continue;
                    }
                    if (layer->size == 3) {
                        uint32_t input_base = (in_base + ic) * layer->ih * layer->iw;
                        uint32_t kernel_base = (oc * in_group + ic) * 9;
                        acc += ai_dot3x3(input + input_base, kernels + kernel_base,
                                         layer->ih, layer->iw,
                                         (int32_t)(oy * layer->stride) - (int32_t)layer->pad,
                                         (int32_t)(ox * layer->stride) - (int32_t)layer->pad);
                        continue;
                    }
                    if (layer->size == 5) {
                        uint32_t input_base = (in_base + ic) * layer->ih * layer->iw;
                        uint32_t kernel_base = (oc * in_group + ic) * 25;
                        acc += ai_dot5x5(input + input_base, kernels + kernel_base,
                                         layer->ih, layer->iw,
                                         (int32_t)(oy * layer->stride) - (int32_t)layer->pad,
                                         (int32_t)(ox * layer->stride) - (int32_t)layer->pad);
                        continue;
                    }
                    for (uint32_t ky = 0; ky < layer->size; ++ky) {
                        int32_t iy = (int32_t)(oy * layer->stride + ky) - (int32_t)layer->pad;
                        if (iy < 0 || iy >= (int32_t)layer->ih) continue;
                        for (uint32_t kx = 0; kx < layer->size; ++kx) {
                            int32_t ix = (int32_t)(ox * layer->stride + kx) - (int32_t)layer->pad;
                            if (ix < 0 || ix >= (int32_t)layer->iw) continue;
                            uint32_t input_index = ((in_base + ic) * layer->ih + (uint32_t)iy) * layer->iw + (uint32_t)ix;
                            uint32_t kernel_index = ((oc * in_group + ic) * layer->size + ky) * layer->size + kx;
                            acc += (int32_t)input[input_index] * (int32_t)kernels[kernel_index];
                        }
                    }
                }
                int32_t value = apply_q24(acc, params[oc * 2]) + params[oc * 2 + 1];
                if (layer->leaky && value < 0) value = apply_q24(value, YOLO_LEAKY_Q24);
                output[(oc * layer->oh + oy) * layer->ow + ox] = clip8(value);
            }
        }
    }
#if YOLO_1X1_ACC32
    return 1;
#endif
}

static void route_layer(const YoloLayer *layer, int8_t *output)
{
    uint32_t offset = 0;
    for (uint32_t j = 0; j < layer->source_count; ++j) {
        int source_index = layer->sources[j];
        const YoloLayer *source_layer = &yolo_layers[source_index];
        const int8_t *source = output_of(source_index);
        uint32_t count = source_layer->oh * source_layer->ow * source_layer->oc;
        for (uint32_t i = 0; i < count; ++i)
            output[offset + i] = clip8(apply_q24(source[i], layer->source_q24[j]));
        offset += count;
    }
}

static void shortcut_layer(const YoloLayer *layer, const int8_t *input, int8_t *output)
{
    const int8_t *source = output_of(layer->sources[0]);
    uint32_t count = layer->oh * layer->ow * layer->oc;
#if YOLO_SHORTCUT_LUT
    int8_shortcut_lut(input, source, output, count, layer->prev_q24,
                      layer->source_q24[0], &shortcut_lut_scratch);
#else
    for (uint32_t i = 0; i < count; ++i) {
        int32_t value = apply_q24(input[i], layer->prev_q24) +
                        apply_q24(source[i], layer->source_q24[0]);
        output[i] = clip8(value);
    }
#endif
}

#if YOLO_POOL_SEPARABLE
/* One inference/layer at a time; this DDR object is never shared with live
 * activations/cache/residual LUT. The original caller owns stable tensors. */
static int8_t pool_separable_scratch[100] __attribute__((aligned(32)));
#if TCM_TEXT && TCM_STACK && YOLO_RGB3_BLOCK && !defined(YOLO_HOST_TEST)
/* Historical section also holds other cold routines. Reuse its existing
 * cached-DDR placement without enlarging the 24KiB TCM code partition. */
#define YOLO_POOL_FUNCTION __attribute__((noinline,section(".ddr_rgb3")))
#endif
#include "pool_separable.h"
#ifdef YOLO_HOST_TEST
static uint32_t pool_separable_fast_calls, pool_separable_fallback_calls;
#endif
#endif
static void maxpool_layer(const YoloLayer *layer, const int8_t *input, int8_t *output)
{
#if YOLO_POOL_SEPARABLE
    if(pool_separable(layer,input,output,pool_separable_scratch,sizeof(pool_separable_scratch))==0){
#ifdef YOLO_HOST_TEST
        ++pool_separable_fast_calls;
#endif
        return;
    }
#ifdef YOLO_HOST_TEST
    ++pool_separable_fallback_calls;
#endif
#endif
    for (uint32_t c = 0; c < layer->oc; ++c) {
        for (uint32_t oy = 0; oy < layer->oh; ++oy) {
            for (uint32_t ox = 0; ox < layer->ow; ++ox) {
                int32_t best = -127;
                for (uint32_t ky = 0; ky < layer->size; ++ky) {
                    int32_t iy = (int32_t)(oy * layer->stride + ky) - (int32_t)layer->pad;
                    if (iy < 0 || iy >= (int32_t)layer->ih) continue;
                    for (uint32_t kx = 0; kx < layer->size; ++kx) {
                        int32_t ix = (int32_t)(ox * layer->stride + kx) - (int32_t)layer->pad;
                        if (ix < 0 || ix >= (int32_t)layer->iw) continue;
                        int32_t value = input[(c * layer->ih + (uint32_t)iy) * layer->iw + (uint32_t)ix];
                        if (value > best) best = value;
                    }
                }
                output[(c * layer->oh + oy) * layer->ow + ox] = clip8(apply_q24(best, layer->prev_q24));
            }
        }
    }
}

static void upsample_layer(const YoloLayer *layer, const int8_t *input, int8_t *output)
{
    for (uint32_t c = 0; c < layer->oc; ++c)
        for (uint32_t oy = 0; oy < layer->oh; ++oy)
            for (uint32_t ox = 0; ox < layer->ow; ++ox) {
                int8_t value = input[(c * layer->ih + oy / layer->stride) * layer->iw + ox / layer->stride];
                output[(c * layer->oh + oy) * layer->ow + ox] = clip8(apply_q24(value, layer->prev_q24));
            }
}

static void passthrough_layer(const YoloLayer *layer, const int8_t *input, int8_t *output)
{
    uint32_t count = layer->oh * layer->ow * layer->oc;
#if YOLO_IDENTITY_FASTPATH
    /* Exact for all256 INT8 codes, including -128 which the original clip
     * maps to -127. Other multipliers retain the original Q24 path. */
    if (layer->prev_q24 == 16777216) {
        for (uint32_t i = 0; i < count; ++i)
            output[i] = clip8(input[i]);
        return;
    }
#endif
    for (uint32_t i = 0; i < count; ++i)
        output[i] = clip8(apply_q24(input[i], layer->prev_q24));
}

static uint32_t fnv_head(int index)
{
    const YoloLayer *layer = &yolo_layers[index];
    const int8_t *data = output_of(index);
    uint32_t count = layer->oh * layer->ow * layer->oc;
    uint32_t hash = 2166136261u;
    for (uint32_t i = 0; i < count; ++i)
        hash = (hash ^ (uint8_t)data[i]) * 16777619u;
    return hash;
}

int main(void)
{
    uart_init(CLK_HZ, BAUD);
    uart_puts("YOLO_FIXED START\n");
#ifndef YOLO_HOST_TEST
    AI_BIAS = 0;
#endif
#if YOLO_UART_IMAGE
    if (!receive_image()) return h07_yolo_failure(3);
    const int8_t *image = uart_image;
#else
    const int8_t *image = yolo_dog_image;
#endif
#if YOLO_TCM_LAYER
    YoloLayer staged_layer;
    if (!yolo_layer_cache_range(&staged_layer)) {
        uart_puts("YOLO_TCM_LAYER_FAIL range\n");
        return h07_yolo_failure(5);
    }
#ifndef YOLO_HOST_TEST
    uart_puts("YOLO_TCM_LAYER start=0x"); uart_puthex((uintptr_t)&staged_layer);
    uart_puts(" bytes="); uart_putdec(sizeof(staged_layer)); uart_putc('\n');
#endif
#endif
#ifndef YOLO_HOST_TEST
#if YOLO_BLOCK_PHASE_PROFILE
    block_phase_calibrate();
#endif
    uint64_t forward_start = rdcycle64();
#endif
    for (uint32_t index = 0; index < YOLO_LAYER_COUNT; ++index) {
#if YOLO_BLOCK_PHASE_PROFILE
        block_phase_index = index;
#endif
#if YOLO_TCM_LAYER
        if (!yolo_layer_stage(&staged_layer, &yolo_layers[index])) {
            uart_puts("YOLO_TCM_LAYER_FAIL copy\n");
            return h07_yolo_failure(5);
        }
        const YoloLayer *layer = &staged_layer;
#else
        const YoloLayer *layer = &yolo_layers[index];
#endif
        const int8_t *input = index ? output_of(index - 1) : image;
#if YOLO_REUSE_ACTIVATIONS
        int8_t *output = arena + yolo_compact_offsets[index];
#else
        int8_t *output = arena + layer->output_offset;
#endif
#if YOLO_LAYER_PROFILE
        uint64_t layer_start = layer_clock();
#endif
        switch (layer->kind) {
        case YOLO_CONV:
#if YOLO_1X1_ACC32
            if (!conv_layer(layer, input, output)) {
#if YOLO_1X1_BLOCK
                uart_puts("AI_1X1_BLOCK_FAIL operator\n");
#else
                uart_puts("AI_1X1_ACC32_FAIL channels\n");
#endif
                return h07_yolo_failure(3);
            }
#else
            conv_layer(layer, input, output);
#endif
            break;
        case YOLO_ROUTE: route_layer(layer, output); break;
        case YOLO_SHORTCUT: shortcut_layer(layer, input, output); break;
        case YOLO_MAXPOOL: maxpool_layer(layer, input, output); break;
        case YOLO_UPSAMPLE: upsample_layer(layer, input, output); break;
        case YOLO_DROPOUT: case YOLO_HEAD:
#if YOLO_IDENTITY_FORWARD
            /* Only certified same-shaped saturated convolution outputs.
             * Make check_identity_forward binds the graph, producer code and
             * inclusive alias lifetimes. Generic INT8 passthrough stays exact. */
            if (yolo_identity_forwarded[index]) break;
#endif
            passthrough_layer(layer, input, output); break;
        default: return h07_yolo_failure(2);
        }
#if defined(YOLO_HOST_TEST) && YOLO_HOST_TRACE
        uart_puts("HOST_LAYER "); uart_putdec(index); uart_putc(' ');
        uart_puthex(fnv_head(index)); uart_putc('\n');
#endif
#if YOLO_LAYER_PROFILE
        layer_cycles[index] = layer_clock() - layer_start;
#endif
        if (index % 10 == 0) uart_putc('.');
    }
#ifndef YOLO_HOST_TEST
    uint64_t forward_cycles = rdcycle64() - forward_start;
    h18_ui_cycles(forward_cycles);
#endif
#if YOLO_TCM_LAYER && !defined(YOLO_HOST_TEST)
    uart_puts("\nYOLO_TCM_LAYER copies="); uart_putdec(YOLO_LAYER_COUNT);
    uart_puts(" verify=PASS\n");
#endif
    uint32_t head0 = fnv_head(121), head1 = fnv_head(130);
#if YOLO_UART_IMAGE
    uint32_t input_hash = 2166136261u;
    for (uint32_t i = 0; i < YOLO_INPUT_BYTES; ++i)
        input_hash = (input_hash ^ (uint8_t)image[i]) * 16777619u;
    if (input_hash == YOLO_DOG_IMAGE_FNV &&
#else
    if (
#endif
        (head0 != YOLO_HEAD0_FNV || head1 != YOLO_HEAD1_FNV)) {
        uart_puts("\nYOLO_FIXED HASH FAIL ");
        uart_puthex(head0); uart_putc(' '); uart_puthex(head1); uart_putc('\n');
        return h07_yolo_failure(1);
    }
    uart_puts("\nYOLO_FIXED HEADS ");
    uart_puthex(head0); uart_putc(' '); uart_puthex(head1); uart_putc('\n');
#if YOLO_UART_IMAGE
    uart_puts(input_hash == YOLO_DOG_IMAGE_FNV ? "YOLO_FIXED PASS\n" :
              "YOLO_FIXED INFERRED\n");
#else
    uart_puts("YOLO_FIXED PASS\n");
#endif
    yolo_print_detections(output_of(121), output_of(130));
#ifndef YOLO_HOST_TEST
    uart_puts("YOLO_FORWARD_CYCLES=0x");
    uart_puthex((uint32_t)(forward_cycles >> 32));
    uart_puthex((uint32_t)forward_cycles);
    uart_putc('\n');
#endif
#if YOLO_LAYER_PROFILE
    /* UART rows are emitted after the forward timer and detection results. */
    print_layer_profile();
#endif
#if YOLO_BLOCK_PHASE_PROFILE
    print_block_phase_profile();
#endif
#ifdef YOLO_HOST_TEST
    extern uint32_t host_ai_calls;
    extern uint32_t host_gpio_out;
    uart_puts("ai_dot9_calls="); uart_putdec(host_ai_calls); uart_putc('\n');
    uart_puts("led_gpio="); uart_puthex(host_gpio_out); uart_putc('\n');
#endif
    return h07_finish_input();
}
