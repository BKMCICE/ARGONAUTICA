#ifndef A91_SCALAR_TESTS_H
#define A91_SCALAR_TESTS_H
static int64_t a91_ref_q(int64_t v,int32_t m){
    int64_t p=v*m;uint64_t mag=(uint64_t)(p<0?-p:p);
    int64_t rounded=(int64_t)((mag+8388608u)/16777216u);
    return p<0?-rounded:rounded;
}
static int8_t a91_ref_activation(int32_t v,uint32_t leaky){
    int64_t x=v;if(leaky&&x<0)x=a91_ref_q(x,1677722);
    return x>127?127:x< -127?-127:(int8_t)x;
}
__attribute__((noinline)) static int a91_scalar_one(int32_t v,uint32_t leaky,uint32_t *count){
    int8_t ref=a91_ref_activation(v,leaky);
    if(a91_activation_control(v,leaky)!=ref||a91_activation_candidate(v,leaky)!=ref||
       a91_quant_control(0,0,v,leaky)!=ref||a91_quant_candidate(0,0,v,leaky)!=ref)return 1;
    ++*count;return 0;
}
static int a91_scalar_tests(uint32_t *count){
    *count=0;
    for(int32_t v=-4096;v<=4096;++v)for(uint32_t l=0;l<2;++l)if(a91_scalar_one(v,l,count))return 1;
    static const int32_t anchors[]={INT32_MIN,INT32_MIN+1,-2147483647,-4194305,-4194304,-4194303,-1000000,-17724,-1266,-1265,-1264,-127,-1,0,1,127,1264,1265,17741,1000000,4194303,4194304,4194305,INT32_MAX-1,INT32_MAX};
    for(uint32_t i=0;i<sizeof(anchors)/sizeof(anchors[0]);++i)for(uint32_t l=0;l<2;++l)if(a91_scalar_one(anchors[i],l,count))return 2;
    uint32_t rng=0x91c0ffeeu;
    for(uint32_t i=0;i<4096;++i){rng=rng*1664525u+1013904223u;int32_t v=(int32_t)(rng&0x7fffffffu);if(rng&0x80000000u)v=-v;for(uint32_t l=0;l<2;++l)if(a91_scalar_one(v,l,count))return 3;}
    static const int32_t accs[]={-147456,-1265,-1264,-9,-1,0,1,9,1264,1265,147456};
    static const int32_t mults[]={-16777216,-8388608,-1677722,-1,0,1,1677722,8388608,16777216};
    static const int32_t biases[]={-1265,-1264,-127,-1,0,1,127,1264,1265};
    for(uint32_t a=0;a<11;++a)for(uint32_t m=0;m<9;++m)for(uint32_t b=0;b<9;++b)for(uint32_t l=0;l<2;++l){
        int64_t v=a91_ref_q(accs[a],mults[m])+biases[b];
        int8_t ref=a91_ref_activation((int32_t)v,l);
        if(a91_quant_control(accs[a],mults[m],biases[b],l)!=ref||a91_quant_candidate(accs[a],mults[m],biases[b],l)!=ref)return 4;
        ++*count;
    }
    return 0;
}
#endif
