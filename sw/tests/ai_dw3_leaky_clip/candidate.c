#include "transport.h"
#define host_dw3_rolling_calls a91_candidate_unused_host_calls
#define main a91_unused_candidate_main
#include "../../yolo_fixed/main.c"
#undef main
#include "leaky_clip.h"
#include "candidate_rolling.h"
int a91_candidate(const YoloLayer*l,const int8_t*x,int8_t*y,const int8_t*w,const int32_t*p){return a91_candidate_rolling(l,x,y,w,p);}
int8_t a91_activation_control(int32_t v,uint32_t l){if(l&&v<0)v=apply_q24(v,YOLO_LEAKY_Q24);return clip8(v);}
int8_t a91_activation_candidate(int32_t v,uint32_t l){return a91_leaky_clip(v,l);}
int8_t a91_quant_control(int32_t a,int32_t m,int32_t b,uint32_t l){return dw3_quant(a,m,b,l);}
int8_t a91_quant_candidate(int32_t a,int32_t m,int32_t b,uint32_t l){return a91_candidate_dw3_quant(a,m,b,l);}
