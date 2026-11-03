#include <stdint.h>
#include "../../yolo_fixed/model_graph.h"
/* Generated verbatim from the current production functions, with SHA binding. */
#include "production_reference.h"
#include "../../common/int8_shortcut_lut.h"

void a65_control(const YoloLayer *layer, const int8_t *input,
                 const int8_t *source, int8_t *output)
{
    a65_control_source = source;
    shortcut_layer(layer, input, output);
}

void a65_candidate(const YoloLayer *layer, const int8_t *input,
                   const int8_t *source, int8_t *output, Int8ShortcutLut *scratch)
{
    int8_shortcut_lut(input, source, output, layer->oh*layer->ow*layer->oc,
                      layer->prev_q24, layer->source_q24[0], scratch);
}
