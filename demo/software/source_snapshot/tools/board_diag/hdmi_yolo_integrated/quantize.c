#include "quantize.h"
__attribute__((section(".ddr_h07")))
int h07_quantize_pixels(const volatile uint8_t *raw,int8_t *chw,uint32_t first,uint32_t count) {
    if(!raw || !chw || first>102400u || count>102400u-first)return 0;
    for(uint32_t i=first;i<first+count;i++) {
        for(uint32_t c=0;c<3u;c++) {
            uint32_t v=raw[3u*i+c];
            chw[c*102400u+i]=(int8_t)((127u*v+127u)/255u);
        }
    }
    return 1;
}
