/* Independent host transport model; no timing prediction. RTL separately tests
 * clocked forwarding, busy ownership, invalid byte enables and reset abort. */
#include "transport.h"
#include <assert.h>
#include <string.h>
uint32_t a31_words,a31_slides,a31_stages,a31_seeds,a31_accums;
static uint32_t regs[10],mode,enabled,seeded,staged,col;
static int8_t pixels[9],weights[9];
void a31_model_reset(unsigned m)
{
    memset(regs,0,sizeof(regs));mode=m;enabled=seeded=staged=col=0;
    a31_words=a31_slides=a31_stages=a31_seeds=a31_accums=0;
}
static void compute(void)
{
    int32_t sum=(int32_t)regs[7];for(unsigned i=0;i<9;++i)sum+=(int32_t)pixels[i]*weights[i];
    regs[9]=(uint32_t)sum;regs[0]=2;
}
uint32_t a31_read(uint32_t a)
{
    if(a==48)return mode?0x41333131u:0;
    if(a==52)return enabled|(seeded==7?4:0)|(staged?8:0)|(mode==3?2:0);
    if(a==0 && (mode==2 || (mode==4 && a31_seeds)))return 1;
    if(a==36)++a31_accums;
    assert(a<40 && a%4==0);return regs[a/4];
}
void a31_write(uint32_t a,uint32_t v)
{
    ++a31_words;
    if(a==52){assert(mode);enabled=v&1;seeded=staged=0;return;}
    if(a==60){assert(enabled && seeded==7 && !staged);col=v;staged=1;++a31_stages;return;}
    if(a==56){assert(enabled && seeded==7 && (!(v>>31)||staged));
        for(unsigned row=0;row<3;++row){unsigned i=row*3;
            if(v>>31){pixels[i]=pixels[i+2];pixels[i+1]=(int8_t)(col>>(row*8));}
            else {pixels[i]=pixels[i+1];pixels[i+1]=pixels[i+2];}
            pixels[i+2]=(int8_t)(v>>(row*8));
        }
        staged=0;++a31_slides;compute();return;
    }
    assert(a<=28 && a%4==0);regs[a/4]=v;
    if(a>=4 && a<=12){unsigned word=a/4-1;seeded|=1u<<word;staged=0;
        for(unsigned b=0;b<4 && word*4+b<9;++b)pixels[word*4+b]=(int8_t)(v>>(b*8));
    }else if(a>=16 && a<=24){unsigned word=a/4-4;seeded=staged=0;
        for(unsigned b=0;b<4 && word*4+b<9;++b)weights[word*4+b]=(int8_t)(v>>(b*8));
    }else if(a==28){seeded=staged=0;}
    else if(a==0 && (v&1)){++a31_seeds;staged=0;compute();}
}
