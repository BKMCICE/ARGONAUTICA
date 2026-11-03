#include "../../common/soc.h"
#include "../../yolo_fixed/model_graph.h"
int a91_control(const YoloLayer*,const int8_t*,int8_t*,const int8_t*,const int32_t*);
int a91_placebo(const YoloLayer*,const int8_t*,int8_t*,const int8_t*,const int32_t*);
int a91_candidate(const YoloLayer*,const int8_t*,int8_t*,const int8_t*,const int32_t*);
int8_t a91_activation_control(int32_t,uint32_t);
int8_t a91_activation_candidate(int32_t,uint32_t);
int8_t a91_quant_control(int32_t,int32_t,int32_t,uint32_t);
int8_t a91_quant_candidate(int32_t,int32_t,int32_t,uint32_t);
