#ifndef A31_DIAG_H
#define A31_DIAG_H
#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
int a31_control(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a31_candidate(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
#endif
