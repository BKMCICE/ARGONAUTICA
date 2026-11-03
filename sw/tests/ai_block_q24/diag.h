#ifndef A20_DIAG_H
#define A20_DIAG_H
#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
int a20_control(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a20_candidate(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
void a20_store(const int32_t *,int8_t *,uint32_t,int32_t,int32_t,uint32_t);
#endif
