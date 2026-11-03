#include "../../common/soc.h"
#include "../../yolo_fixed/model_graph.h"
int a96_control(const YoloLayer*,const int8_t*,int8_t*);
int a96_placebo(const YoloLayer*,const int8_t*,int8_t*);
int a96_candidate(const YoloLayer*,const int8_t*,int8_t*,int8_t*,uint32_t);
