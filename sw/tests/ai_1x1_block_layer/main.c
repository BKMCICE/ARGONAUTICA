/* Exercise the production operator, original CHW scalar oracle, Q24, guards,
 * weight residency and (host only) dispatch/error handling. */
#ifdef YOLO_HOST_TEST
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "host_mmio.h"
#endif
#define main yolo_app_main
#include "../../yolo_fixed/main.c"
#undef main
#ifdef YOLO_HOST_TEST
uint32_t host_ai_calls;
static const uint32_t widths[]={1,4,8,9,10,17,18,19,32,64,223,224};
static const uint32_t spaces[]={1,7,8,9,17},outputs_list[]={1,3,4,5,8,13};
static int8_t input[3*224*3*33+16],weights[3*13*224+16],actual[3*13*3*17+16];
#else
volatile uint32_t block_layer_result;
/* GCC lowers aggregate initialization to memset even in a freestanding TU.
 * This diagnostic supplies its own bounded byte store, not a C runtime. */
void *memset(void *dest, int value, __SIZE_TYPE__ count) {
    volatile unsigned char *p=(volatile unsigned char *)dest;
    for(__SIZE_TYPE__ i=0;i<count;++i) p[i]=(unsigned char)value;
    return dest;
}
static const uint32_t widths[]={4,10,224},spaces[]={1,9},outputs_list[]={1,5};
static int8_t input[224*2*17+16],weights[10*224+16],actual[4*2*17+16];
static int8_t baseline[4*2*17+16];
#endif
static int32_t params[2*39];
static int32_t scale(int64_t value,int32_t m) {
    int64_t v=value*m,n=((v<0?-v:v)+8388608)/16777216;
    return (int32_t)(v<0?-n:n);
}
static uint32_t hash(const int8_t *p,uint32_t n) {
    uint32_t h=2166136261u;for(uint32_t i=0;i<n;++i) h=(h^(uint8_t)p[i])*16777619u;return h;
}
static void prepare(uint32_t pattern) {
    for(uint32_t i=0;i<sizeof(input);++i) input[i]=pattern%3==0?(i&1?-128:127):pattern%3==1?-128:(int8_t)(i*73u+pattern*19u);
    for(uint32_t i=0;i<sizeof(weights);++i) weights[i]=pattern%3==1?-128:(int8_t)(i*59u+pattern*31u);
    for(uint32_t i=0;i<39;++i) {params[2*i]=(i&1?-1:1)*(pattern%3==1?256:16384+(int32_t)i*29);params[2*i+1]=(int32_t)i-8;}
    for(uint32_t i=0;i<sizeof(actual);++i) actual[i]=0x5a;
}
static int check(const YoloLayer *l,uint32_t channels,uint32_t outputs) {
    for(uint32_t oc=0;oc<l->oc;++oc) for(uint32_t y=0;y<l->oh;++y) for(uint32_t x=0;x<l->ow;++x) {
        int64_t dot=0;
        for(uint32_t c=0;c<channels;++c)
            dot+=(int32_t)input[8+((oc/outputs)*channels+c)*l->ih*l->iw+y*l->stride*l->iw+x*l->stride]*weights[8+oc*channels+c];
        int32_t v=scale(dot,params[2*oc])+params[2*oc+1];
        if(l->leaky && v<0) v=scale(v,1677722);
        if(v>127) v=127;
        if(v< -127) v=-127;
        if(actual[8+(oc*l->oh+y)*l->ow+x]!=v) return 1;
    }
    for(uint32_t i=0;i<sizeof(actual);++i)
        if((i<8 || i>=8+l->oc*l->oh*l->ow) && actual[i]!=0x5a) return 2;
    return 0;
}
#if YOLO_BLOCK_INPUT_CACHE && defined(YOLO_HOST_TEST)
/* Independent byte-wise layout oracle, including all zero padding bytes. */
static int cache_layout(const YoloLayer *l,const int8_t *src,uint32_t channels) {
    uint32_t plane=l->ih*l->iw,out_plane=l->oh*l->ow,blocks=(channels+8)/9;
    src+=(l->groups-1)*channels*plane;
    for(uint32_t b=0;b<blocks;++b) for(uint32_t px=0;px<out_plane;++px)
    for(uint32_t word=0;word<3;++word) {
        uint32_t expected=0;
        for(uint32_t byte=0;byte<4;++byte) {
            uint32_t lane=word*4+byte,c=b*9+lane;
            if(lane<9 && c<channels)
                expected|=(uint32_t)(uint8_t)src[c*plane+(px/l->ow)*l->stride*l->iw+(px%l->ow)*l->stride]<<(byte*8);
        }
        if(block_input_cache[(b*out_plane+px)*3+word]!=expected) return 1;
    }
    return 0;
}
static int cache_capacity_case(uint32_t pixels) {
    uint32_t ni=224*pixels,nw=224*5,no=5*pixels;
    int8_t *src=malloc(ni+16),*k=malloc(nw+16),*out=malloc(no+16);
    if(!src || !k || !out) return 1;
    for(uint32_t i=0;i<ni+16;++i) src[i]=(int8_t)(i%5)-2;
    for(uint32_t i=0;i<nw+16;++i) k[i]=(int8_t)(i%3)-1;
    memset(out,0x5a,no+16);
    for(uint32_t oc=0;oc<5;++oc) {params[oc*2]=8388608;params[oc*2+1]=(int32_t)oc-2;}
    YoloLayer l={0};l.kind=YOLO_CONV;l.size=l.stride=l.groups=l.ih=l.oh=1;
    l.iw=l.ow=pixels;l.ic=224;l.oc=5;l.leaky=1;
    a03_reset(0);uint32_t before=host_block_cached_groups;
    block_input_cache[0]=0x13579bdf;
    uint32_t oldcache=hash((const int8_t *)block_input_cache,sizeof(block_input_cache));
    uint32_t ih=hash(src,ni+16),wh=hash(k,nw+16);
    if(conv1x1_block(&l,src+8,out+8,k+8,params,224,5)) return 2;
    if(host_block_cached_groups-before!=(pixels==1024?1u:0u)) return 3;
    if(pixels==1024 ? cache_layout(&l,src+8,224) : hash((const int8_t *)block_input_cache,sizeof(block_input_cache))!=oldcache) return 4;
    for(uint32_t oc=0;oc<5;++oc) for(uint32_t px=0;px<pixels;++px) {
        int64_t dot=0;
        for(uint32_t c=0;c<224;++c) dot+=(int32_t)src[8+c*pixels+px]*k[8+oc*224+c];
        int32_t v=scale(dot,8388608)+(int32_t)oc-2;
        if(v<0) v=scale(v,1677722);
        if(v>127) v=127;
        if(v< -127) v=-127;
        if(out[8+oc*pixels+px]!=v) return 5;
    }
    for(uint32_t i=0;i<8;++i) if(out[i]!=0x5a || out[8+no+i]!=0x5a) return 6;
    if(hash(src,ni+16)!=ih || hash(k,nw+16)!=wh || a03_weight_words!=5*25*3 || a03_starts!=2*((pixels+7)/8)) return 7;
    free(src);free(k);free(out);return 0;
}
#endif
int main(void) {
    uint32_t cases=0,guards=0;int rc=0;
#ifdef YOLO_HOST_TEST
    a03_reset(0);
#else
    /* A mismatched bitstream must not reach a legacy register write. */
    if(AI_BLOCK_READ(AI_BLOCK_REG_ID)!=AI_BLOCK_ID) return 90;
    AI_BIAS=0;
#endif
    for(uint32_t groups=1;groups<=
#ifdef YOLO_HOST_TEST
        3
#else
        2
#endif
        ;++groups)
    for(uint32_t ci=0;ci<sizeof(widths)/sizeof(widths[0]);++ci)
    for(uint32_t si=0;si<sizeof(spaces)/sizeof(spaces[0]);++si)
    for(uint32_t oi=0;oi<sizeof(outputs_list)/sizeof(outputs_list[0]);++oi)
    for(uint32_t stride=1;stride<=2;++stride) {
        uint32_t c=widths[ci],o=outputs_list[oi];YoloLayer l={0};
        l.kind=YOLO_CONV;l.size=1;l.stride=stride;l.groups=groups;l.ic=groups*c;l.oc=groups*o;
        l.ih=
#ifdef YOLO_HOST_TEST
            3;
#else
            1;
#endif
        l.oh=(l.ih+stride-1)/stride;l.ow=spaces[si];l.iw=(l.ow-1)*stride+1;l.leaky=cases&1;
        prepare(cases);uint32_t ih=hash(input,sizeof(input)),wh=hash(weights,sizeof(weights));
#if YOLO_BLOCK_INPUT_CACHE && defined(YOLO_HOST_TEST)
        uint32_t cached_before=host_block_cached_groups,cache_words=((c+8)/9)*l.oh*l.ow*3;
        if(cache_words<BLOCK_INPUT_CACHE_WORDS) block_input_cache[cache_words]=0x12345678;
#endif
#ifdef YOLO_HOST_TEST
        uint32_t before=a03_weight_words,starts=a03_starts;
#endif
        rc=conv1x1_block(&l,input+8,actual+8,weights+8,params,c,o);if(rc) return 10;
        rc=check(&l,c,o);if(rc) return 11+rc;
        if(hash(input,sizeof(input))!=ih || hash(weights,sizeof(weights))!=wh) return 14;
#if YOLO_BLOCK_INPUT_CACHE && defined(YOLO_HOST_TEST)
        if(host_block_cached_groups-cached_before!=(o>4?groups:0)) return 60;
        if(o>4 && cache_layout(&l,input+8,c)) return 61;
        if(cache_words<BLOCK_INPUT_CACHE_WORDS && block_input_cache[cache_words]!=0x12345678) return 62;
#endif
#ifdef YOLO_HOST_TEST
        if(a03_weight_words-before!=groups*o*((c+8)/9)*3) return 15;
        if(a03_starts-starts!=groups*((o+3)/4)*l.oh*((l.ow+7)/8)) return 16;
#endif
        ++cases;
    }
    {
        YoloLayer l={0};l.kind=YOLO_CONV;l.size=1;l.stride=1;l.groups=1;l.ic=4;l.oc=1;
        l.ih=l.oh=1;l.iw=l.ow=9;
#ifdef YOLO_HOST_TEST
        uint32_t reads=a03_reads,writes=a03_writes;
#endif
#define BAD(expr) do {YoloLayer v=l;expr; if(conv1x1_block(&v,input,actual,weights,params,v.ic,v.oc)!=AI_BLOCK_BAD_SHAPE) return 20; ++guards;} while(0)
        BAD(v.stride=0);BAD(v.groups=0);BAD(v.ic=0);BAD(v.ic=225);BAD(v.oc=0);
        BAD(v.groups=3);BAD(v.pad=1);BAD(v.size=3);BAD(v.kind=YOLO_ROUTE);
        BAD(v.ow=10);BAD(v.oh=2);BAD(v.iw=0);BAD(v.ih=0);BAD(v.ow=0);
        BAD(v.ih=UINT32_MAX;v.iw=2);BAD(v.oc=UINT32_MAX);
#undef BAD
        if(conv1x1_block(0,0,0,0,0,1,1)!=AI_BLOCK_BAD_SHAPE) return 21;
        ++guards;
#ifdef YOLO_HOST_TEST
        if(a03_reads!=reads || a03_writes!=writes) return 29;
        for(unsigned mode=1;mode<=6;++mode) {
            prepare(7);a03_reset(mode);
            int expect=mode==1?AI_BLOCK_UNSUPPORTED:mode==3 || mode==6?AI_BLOCK_TIMEOUT:AI_BLOCK_HW_ERROR;
            if(conv1x1_block(&l,input+8,actual+8,weights+8,params,4,1)!=expect) return 22;
            if(mode<=2 && a03_writes) return 23;
            if(mode!=6) {for(unsigned i=0;i<sizeof(actual);++i) if(actual[i]!=0x5a) return 24;}
            else {for(unsigned i=8+8;i<sizeof(actual);++i) if(actual[i]!=0x5a) return 25;}
            ++guards;
        }
        /* Actual dispatcher, original model tensors, both hardware-present and
         * missing-ID fallback. Compare complete output, not a direct test stub. */
        l=yolo_layers[3];l.ih=l.oh=1;l.iw=l.ow=9;
        int8_t saved[36];
        for(unsigned mode=0;mode<=1;++mode) {
            prepare(8);a03_reset(mode);
            if(!conv_layer(&l,input,actual)) return 26;
            if(!mode) memcpy(saved,actual,sizeof(saved));
            else if(memcmp(saved,actual,sizeof(saved)) || a03_writes) return 27;
        }
        a03_reset(4);if(conv_layer(&l,input,actual)!=0) return 28;
#else
        /* Whole production operator comparison: includes CHW packing, weights,
         * spatial loops, Q24, bias, leaky and clipping on BOTH implementations. */
        l.ic=224;l.oc=4;l.ih=l.oh=2;l.iw=l.ow=17;l.leaky=1;prepare(11);
        uint64_t t=rdcycle64();
        if(!conv1x1_input_reuse(&l,input+8,baseline+8,weights+8,params,224,4)) return 30;
        uint64_t legacy=rdcycle64()-t;t=rdcycle64();
        if(conv1x1_block(&l,input+8,actual+8,weights+8,params,224,4)) return 31;
        uint64_t block=rdcycle64()-t;
        for(unsigned i=0;i<4*2*17;++i) if(actual[8+i]!=baseline[8+i]) return 32;
        if(check(&l,224,4)) return 33;
        uart_puts("A03_LAYER legacy_cycles=");uart_putdec((uint32_t)legacy);
        uart_puts(" block_cycles=");uart_putdec((uint32_t)block);uart_putc('\n');
#endif
    }
#ifdef YOLO_HOST_TEST
#if YOLO_BLOCK_INPUT_CACHE
    if(cache_capacity_case(1024) || cache_capacity_case(1025)) return 63;
    cases+=2;
    {
        YoloLayer l={0};l.kind=YOLO_CONV;l.size=l.stride=l.groups=l.ih=l.oh=1;
        l.ic=4;l.oc=8;l.iw=l.ow=9;
        uint32_t reads=a03_reads,writes=a03_writes,groups=host_block_cached_groups;
        if(conv1x1_block(&l,(int8_t *)block_input_cache,actual,weights,params,4,8)!=AI_BLOCK_BAD_SHAPE ||
           conv1x1_block(&l,input,(int8_t *)block_input_cache,weights,params,4,8)!=AI_BLOCK_BAD_SHAPE ||
           conv1x1_block(&l,input,actual,(int8_t *)block_input_cache,params,4,8)!=AI_BLOCK_BAD_SHAPE ||
           conv1x1_block(&l,input,actual,weights,(int32_t *)block_input_cache,4,8)!=AI_BLOCK_BAD_SHAPE) return 64;
        if(conv1x1_block(&l,(int8_t *)(UINTPTR_MAX-8),actual,weights,params,4,8)!=AI_BLOCK_BAD_SHAPE ||
           conv1x1_block(&l,input,(int8_t *)(UINTPTR_MAX-8),weights,params,4,8)!=AI_BLOCK_BAD_SHAPE ||
           conv1x1_block(&l,input,actual,(int8_t *)(UINTPTR_MAX-8),params,4,8)!=AI_BLOCK_BAD_SHAPE ||
           conv1x1_block(&l,input,actual,weights,(int32_t *)(UINTPTR_MAX-8),4,8)!=AI_BLOCK_BAD_SHAPE) return 66;
        if(reads!=a03_reads || writes!=a03_writes || groups!=host_block_cached_groups) return 65;
        guards+=8;
    }
    printf("A07_CACHE_OPERATOR_SCALAR_PASS cases=%u guards=%u\n",cases,guards);
    return cases==2162 && guards==31 ? 0:40;
#else
    printf("A03_OPERATOR_SCALAR_PASS cases=%u guards=%u\n",cases,guards);
    return cases==2160 && guards==23 ? 0:40;
#endif
#else
    uart_puts("A03_OPERATOR_PASS cases=");uart_putdec(cases);uart_puts(" guards=");uart_putdec(guards);uart_putc('\n');
    block_layer_result=cases==48 && guards==17 ? 1:3;return block_layer_result==1?0:40;
#endif
}
