/* Observational physical bring-up. Separate ELF, no production/timing changes.
 * Print each sub-result to localize main_return=20 in the compact harness. */
#define main a32_included_diagnostic_main
#include "main.c"
#undef main
static void hexfield(const char *s,uint32_t v){uart_puts(s);uart_puthex(v);}
static int mini(int px,int weight,int mult,int bias,unsigned leaky,int want)
{
    AI_BLOCK_WRITE(0x204,0);AI_BLOCK_WRITE(0x104,4);AI_BLOCK_WRITE(0x204,1|(leaky?2:0));
    AI_BLOCK_WRITE(0x208,0);AI_BLOCK_WRITE(0x20c,(uint32_t)mult);
    uint32_t mread=AI_BLOCK_READ(0x20c);
    AI_BLOCK_WRITE(0x210,(uint32_t)bias);
    AI_BLOCK_WRITE(0x10c,0);AI_BLOCK_WRITE(0x110,(uint8_t)weight);AI_BLOCK_WRITE(0x110,0);AI_BLOCK_WRITE(0x110,0);
    AI_BLOCK_WRITE(0x114,0);AI_BLOCK_WRITE(0x118,(uint8_t)px);AI_BLOCK_WRITE(0x118,0);AI_BLOCK_WRITE(0x118,0);
    AI_BLOCK_WRITE(0x108,0x10111);AI_BLOCK_WRITE(0x104,1);
    unsigned count=0;uint32_t status;
    do{status=AI_BLOCK_READ(0x104);++count;}while(!(status&2)&&count<100000);
    uint32_t qs=AI_BLOCK_READ(0x200),packed=0,raw=0;
    if(status==2){packed=AI_BLOCK_READ(0x220);raw=AI_BLOCK_READ(0x120);}
    uart_puts("A32_DEBUG_MINI");hexfield(" status=",status);hexfield(" qstatus=",qs);
    hexfield(" mread=",mread);hexfield(" raw=",raw);hexfield(" packed=",packed);hexfield(" want=",(uint8_t)want);
    uart_puts(" items=");uart_putdec(AI_BLOCK_READ(0x22c));uart_puts(" cycles=");uart_putdec(AI_BLOCK_READ(0x228));uart_putc('\n');
    return status!=2 || raw!=(uint32_t)(px*weight) || packed!=(uint8_t)want || mread!=(uint32_t)mult;
}
int main(void)
{
    uart_init(CLK_HZ,BAUD);AI_BIAS=0;
    hexfield("A32_DEBUG_ID=",AI_BLOCK_READ(0x28));uart_putc('\n');
    YoloLayer l=shape(0);prepare(1);int oldrc=run(0,&l),newrc=-99,comparison=-99;
    if(!oldrc)newrc=run(1,&l);
    if(!oldrc&&!newrc)comparison=check(&l,0,1);
    uart_puts("A32_DEBUG_WARM");hexfield(" control_rc=",(uint32_t)oldrc);hexfield(" candidate_rc=",(uint32_t)newrc);
    hexfield(" compare=",(uint32_t)comparison);hexfield(" prior_hash=",hash(prior+8,l.oc*l.oh*l.ow));
    hexfield(" actual_hash=",hash(actual+8,l.oc*l.oh*l.ow));hexfield(" expected_hash=",a32_short_expected[0]);
    hexfield(" status=",AI_BLOCK_READ(0x104));hexfield(" qstatus=",AI_BLOCK_READ(0x200));
    hexfield(" mode=",AI_BLOCK_READ(0x204));uart_puts(" items=");uart_putdec(AI_BLOCK_READ(0x22c));uart_putc('\n');
    unsigned printed=0;
    for(unsigned i=0;i<l.oc*l.oh*l.ow&&printed<12;++i)if(actual[8+i]!=prior[8+i]){
        uart_puts("A32_DEBUG_DIFF index=");uart_putdec(i);hexfield(" prior=",(uint8_t)prior[8+i]);hexfield(" actual=",(uint8_t)actual[8+i]);uart_putc('\n');++printed;
    }
    if(AI_BLOCK_READ(0x104)&1u){uart_puts("A32_DEBUG_BUSY_ABORT\n");return 1;}
    int bad=oldrc||newrc||comparison;
    bad|=mini(3,5,8388608,-1,0,7);
    bad|=mini(-3,5,8388608,-1,1,-1);
    bad|=mini(127,-128,16384,5,0,-11);
    bad|=mini(-128,-128,16384,-8,1,8);
    uart_puts("A32_DEBUG_COMPLETE bad=");uart_putdec(bad!=0);uart_putc('\n');
    return bad?1:0;
}
