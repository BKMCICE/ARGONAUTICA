#ifndef H07_QUANTIZE_H
#define H07_QUANTIZE_H
#include <stdint.h>
/* Fixed RAW RGB888 -> RGB planar Q127; no scaling or range expansion. */
int h07_quantize_pixels(const volatile uint8_t *raw,int8_t *chw,uint32_t first,uint32_t count);
#endif
