/* Fixed-point YOLO head decode and class-wise NMS for the sample image. */
#include "soc.h"
#include "model_graph.h"
#include "postprocess_lut.h"

#define MAX_CANDIDATES 256
#define SCORE_THRESHOLD_Q15 8192

typedef struct {
    int32_t x0, y0, x1, y1; /* Q8 pixels, clipped to 320x320 */
    uint16_t score;
    uint8_t class_id;
    uint8_t removed;
} Detection;

static Detection candidates[MAX_CANDIDATES];
static uint32_t candidate_count;

static int32_t clip_coord(int64_t value)
{
    if (value < 0) return 0;
    if (value > 320 * 256) return 320 * 256;
    return (int32_t)value;
}

static void collect_head(const int8_t *data, uint32_t number, const YoloLayer *layer)
{
    const uint16_t *sig = number ? yolo_sigmoid_1 : yolo_sigmoid_0;
    const uint32_t *exponential = number ? yolo_exp_1 : yolo_exp_0;
    uint32_t cells = layer->oh * layer->ow;
    uint32_t stride = 320 / layer->ow;
    for (uint32_t anchor = 0; anchor < 3; ++anchor) {
        uint32_t base = anchor * 85 * cells;
        for (uint32_t row = 0; row < layer->oh; ++row) {
            for (uint32_t col = 0; col < layer->ow; ++col) {
                uint32_t pos = row * layer->ow + col;
                uint16_t objectness = sig[(uint8_t)data[base + 4 * cells + pos]];
                if (objectness < SCORE_THRESHOLD_Q15) continue;
                uint8_t best_class = 0;
                int8_t best_logit = -128;
                for (uint32_t cls = 0; cls < 80; ++cls) {
                    int8_t logit = data[base + (5 + cls) * cells + pos];
                    if (logit > best_logit) { best_logit = logit; best_class = (uint8_t)cls; }
                }
                uint32_t score = ((uint32_t)objectness * sig[(uint8_t)best_logit] + 16384) >> 15;
                if (score < SCORE_THRESHOLD_Q15 || candidate_count == MAX_CANDIDATES) continue;
                uint16_t sx = sig[(uint8_t)data[base + pos]];
                uint16_t sy = sig[(uint8_t)data[base + cells + pos]];
                uint32_t ew = exponential[(uint8_t)data[base + 2 * cells + pos]];
                uint32_t eh = exponential[(uint8_t)data[base + 3 * cells + pos]];
                int64_t cx = (((int64_t)col * 32768 + sx) * stride * 256 + 16384) >> 15;
                int64_t cy = (((int64_t)row * 32768 + sy) * stride * 256 + 16384) >> 15;
                int64_t bw = ((int64_t)yolo_anchors[number][anchor][0] * ew + 128) >> 8;
                int64_t bh = ((int64_t)yolo_anchors[number][anchor][1] * eh + 128) >> 8;
                Detection *item = &candidates[candidate_count++];
                item->x0 = clip_coord(cx - bw / 2);
                item->y0 = clip_coord(cy - bh / 2);
                item->x1 = clip_coord(cx + bw / 2);
                item->y1 = clip_coord(cy + bh / 2);
                item->score = (uint16_t)score;
                item->class_id = best_class;
                item->removed = 0;
            }
        }
    }
}

static int32_t positive(int32_t value) { return value > 0 ? value : 0; }

static int overlap_exceeds_45(const Detection *a, const Detection *b)
{
    int32_t x0 = a->x0 > b->x0 ? a->x0 : b->x0;
    int32_t y0 = a->y0 > b->y0 ? a->y0 : b->y0;
    int32_t x1 = a->x1 < b->x1 ? a->x1 : b->x1;
    int32_t y1 = a->y1 < b->y1 ? a->y1 : b->y1;
    int64_t intersection = (int64_t)positive(x1 - x0) * positive(y1 - y0);
    int64_t area_a = (int64_t)positive(a->x1 - a->x0) * positive(a->y1 - a->y0);
    int64_t area_b = (int64_t)positive(b->x1 - b->x0) * positive(b->y1 - b->y0);
    int64_t union_area = area_a + area_b - intersection;
    return union_area > 0 && intersection * 100 >= union_area * 45;
}

static void print_q8(int32_t value)
{
    uart_putdec((uint32_t)((value + 128) >> 8));
}

/* The optional post8 word stores exceed the old hot image by 20 bytes.
 * Detection reporting runs after the forward timer stops. Reuse the existing
 * RGB3 cold section; hot inference and the TCM stack keep their budgets. */
#if YOLO_POST8_WORD_STORE && defined(TCM_STACK) && YOLO_RGB3_BLOCK
__attribute__((section(".ddr_rgb3"), noinline))
#endif
void yolo_print_detections(const int8_t *head0, const int8_t *head1)
{
    candidate_count = 0;
    collect_head(head0, 0, &yolo_layers[121]);
    collect_head(head1, 1, &yolo_layers[130]);
    /* Selection sort is small at this threshold and avoids dynamic memory. */
    for (uint32_t i = 0; i < candidate_count; ++i) {
        uint32_t best = i;
        for (uint32_t j = i + 1; j < candidate_count; ++j)
            if (candidates[j].score > candidates[best].score) best = j;
        Detection tmp = candidates[i]; candidates[i] = candidates[best]; candidates[best] = tmp;
    }
    uint32_t shown = 0;
    uint8_t best_class = 0;
    for (uint32_t i = 0; i < candidate_count && shown < 10; ++i) {
        Detection *item = &candidates[i];
        if (item->removed) continue;
        if (shown == 0) best_class = item->class_id;
        uart_puts(yolo_names[item->class_id]); uart_putc(' ');
        uart_putdec(((uint32_t)item->score * 1000) / 32767); uart_puts("/1000 [");
        print_q8(item->x0); uart_putc(','); print_q8(item->y0); uart_putc(',');
        print_q8(item->x1); uart_putc(','); print_q8(item->y1); uart_puts("]\n");
        ++shown;
        for (uint32_t j = i + 1; j < candidate_count; ++j)
            if (candidates[j].class_id == item->class_id &&
                overlap_exceeds_45(item, &candidates[j])) candidates[j].removed = 1;
    }
    /* Board LEDs show completion (bit 7) and the top COCO class modulo 128.
     * UART carries the full class name, score and box coordinates. */
#ifdef YOLO_HOST_TEST
    extern uint32_t host_gpio_out;
    host_gpio_out = shown ? (0x80u | best_class) : 0xFFu;
#else
    GPIO_OUT = shown ? (0x80u | best_class) : 0xFFu;
#endif
    uart_puts("detections="); uart_putdec(shown); uart_putc('\n');
}
