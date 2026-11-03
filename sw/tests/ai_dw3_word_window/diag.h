#include "../../common/soc.h"
#include "../../yolo_fixed/model_graph.h"
int a86_control(const YoloLayer*,const int8_t*,int8_t*,const int8_t*,const int32_t*);
int a86_placebo(const YoloLayer*,const int8_t*,int8_t*,const int8_t*,const int32_t*);
int a86_candidate(const YoloLayer*,const int8_t*,int8_t*,const int8_t*,const int32_t*);
