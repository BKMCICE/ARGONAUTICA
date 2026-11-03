#include "soc.h"
#include "ai_mac_dw3x3.h"

static int8_t pixels[35], weights[9];

int main(void)
{
    const uint32_t heights[3]={1,2,5}, widths[3]={1,3,7};
    uint32_t cases=0;
    AI_BIAS=0;
    for(uint32_t hi=0;hi<3;++hi) for(uint32_t wi=0;wi<3;++wi)
    for(uint32_t kernel=0;kernel<4;++kernel) {
        uint32_t height=heights[hi],width=widths[wi];
        for(uint32_t i=0;i<sizeof(pixels);++i)
            pixels[i]=(int8_t)((i*43u+kernel*71u)&255u);
        for(uint32_t i=0;i<9;++i)
            weights[i]=(int8_t)((i*89u+kernel*127u)&255u);
        if(ai_dot9_packed(0,0,0,0xdeadbeef,0x89abcdef,0x55)!=0) return 1;
        ai_load_1x1_weights(weights,9);
        uint32_t resident[3]={AI_WGT0,AI_WGT1,AI_WGT2};
        for(uint32_t lane=0;lane<9;++lane)
            if((int8_t)(resident[lane>>2]>>((lane&3u)*8u))!=weights[lane]) return 2;
        if(resident[2]&0xffffff00u) return 3;
        for(uint32_t stride=1;stride<=2;++stride)
        for(int32_t top=-2;top<=(int32_t)height;top+=(int32_t)stride)
        for(int32_t left=-2;left<=(int32_t)width;left+=(int32_t)stride) {
            int32_t expected=0;
            for(int32_t ky=0;ky<3;++ky) for(int32_t kx=0;kx<3;++kx) {
                int32_t y=top+ky,x=left+kx;
                if(y>=0 && y<(int32_t)height && x>=0 && x<(int32_t)width)
                    expected+=(int32_t)pixels[y*width+x]*weights[ky*3+kx];
            }
            if(ai_dot3x3_loaded(pixels,height,width,top,left)!=expected) {
                uart_puts("AI_DW3X3_REUSE_FAIL dot\n"); return 4;
            }
            if(AI_WGT0!=resident[0] || AI_WGT1!=resident[1] || AI_WGT2!=resident[2]) return 5;
            ++cases;
        }
    }
    uart_puts("AI_DW3X3_REUSE_PASS cases="); uart_putdec(cases); uart_putc('\n');
    return cases==1720 ? 0 : 6;
}
