#include <stdint.h>
#define R(a) (*(volatile uint32_t *)(a))
extern void readonly_store(volatile uint32_t *);
static void fence_i(void){__asm__ volatile(".word 0x0000100f":::"memory");}
static void delay(void){for(volatile unsigned i=0;i<50;++i){}}
static uint32_t hash(void){uint32_t h=2166136261u;for(unsigned n=0;n<384;++n)h=(h^*(volatile uint8_t *)(0x80400000u+n))*16777619u;return h;}
int main(void){
    R(0x40003000)=3;R(0x40005000)=3;
    if(R(0x40006000)!=0x48304331u)return 1;
    if(R(0x40006020)!=0x48303449u)return 18;
    R(0x4000602c)=1;while(!(R(0x40006024)&2)){}
    if(R(0x40006028)!=1||R(0x40006030)!=0x48303449u||R(0x40006038)!=0x00020000u||R(0x40006014)!=0)return 19;
    uint32_t frozen_flags=R(0x40006034);delay();
    if(R(0x40006034)!=frozen_flags||R(0x40006028)!=1)return 20;
    R(0x40001008)=1;R(0x40001000)=0x31;
    while(!(R(0x4000100c)&1)){}R(0x4000100c)=1;
    while(R(0x40001004)!=255){}
    R(0x40000008)=16;R(0x4000000c)=1;R(0x40001000)=0x32;
    while(!(R(0x40000004)&4)){}if((R(0x40000000)&0x1ff)!=0x1a6)return 2;
    R(0x4000000c)=0;R(0x40000000)=0x55;
    R(0x40002000)=1;delay();if(R(0x40002000)!=1)return 3;R(0x40002000)=0;
    R(0x40002008)=0;R(0x4000200c)=0;delay();R(0x40002008)=0xffffffffu;R(0x4000200c)=0xffffffffu;
    uint32_t t=R(0x40002010);delay();if(R(0x40002010)<=t)return 4;
    if(R(0x4000402c)!=0x41343831u)return 5;
    R(0x40004004)=0x01010101;R(0x40004008)=0x01010101;R(0x4000400c)=1;
    R(0x40004010)=0x02020202;R(0x40004014)=0x02020202;R(0x40004018)=2;R(0x4000401c)=0;R(0x40004000)=1;
    while(!(R(0x40004000)&2)){}if(R(0x40004024)!=18||R(0x40004020)!=18)return 6;
    // Actual CPU MMIO: invalid maximal shape is rejected, a partial shape
    // write cannot replace the accepted valid shape, and raw MAC statistics
    // stay exactly three LOAD/MULT/ADD clocks for one nine-lane dot.
    R(0x40004108)=0x00091911;R(0x40004104)=1;
    if(R(0x40004104)!=6||R(0x40004124)!=0||R(0x40004128)!=0)return 15;
    R(0x40004104)=4;R(0x40004108)=0x00090111;
    *(volatile uint8_t *)0x40004108=0;
    if(R(0x40004108)!=0x00090111||R(0x40004104)!=4)return 16;
    R(0x40004104)=4;R(0x4000410c)=0;
    R(0x40004110)=0x02020202;R(0x40004110)=0x02020202;R(0x40004110)=2;
    R(0x40004114)=0;
    R(0x40004118)=0x01010101;R(0x40004118)=0x01010101;R(0x40004118)=1;
    R(0x40004104)=1;while(!(R(0x40004104)&2)){}
    if(R(0x40004104)!=2||R(0x40004120)!=18||R(0x40004124)!=3||R(0x40004128)!=1)return 17;
    volatile uint32_t *code=(volatile uint32_t *)0x80000000;
    uint32_t(*f)(void)=(uint32_t(*)(void))0x80000000;
    code[0]=0x01100513;code[1]=0x00008067;fence_i();if(f()!=17)return 7;
    code[0]=0x02200513;fence_i();if(f()!=34)return 8;
    R(0x80400000)=0x11223344;
    while(!(R(0x4000601c)&1)){}
    R(0x40006000)=1;if(f()!=34)return 9;
    while(R(0x40006004)&2){}if((R(0x40006004)&12)!=4)return 10;
    uint32_t h=hash();R(0x7004)=h;if(h!=0xbe90c9a5u)return 11;
    readonly_store((volatile uint32_t *)0x80400000);
    if(R(0x7008)!=7||hash()!=h)return 12;
    if(!R(0x40003004)||!R(0x40003008))return 13;
    if(!R(0x40005004)||!R(0x40005008)||!R(0x4000500c)||!R(0x40005010))return 14;
    R(0x40006000)=4;while(R(0x40006004)&16){}
    return 0x600d0001u;
}
