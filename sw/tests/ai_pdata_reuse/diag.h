#ifndef A28_DIAG_H
#define A28_DIAG_H
#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
int a28_control(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a28_candidate(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
void a28_store(const int32_t *,int8_t *,uint32_t,int32_t,int32_t,uint32_t);
#endif
