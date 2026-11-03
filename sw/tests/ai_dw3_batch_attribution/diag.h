#include "../../common/soc.h"
#include "../../yolo_fixed/model_graph.h"
int a90_control(const YoloLayer*,const int8_t*,int8_t*,const int8_t*,const int32_t*);
int a90_post(const YoloLayer*,const int8_t*,int8_t*,const int8_t*,const int32_t*);
int a90_raw(const YoloLayer*,const int8_t*,int8_t*,const int8_t*,const int32_t*);
