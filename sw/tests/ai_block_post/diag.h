#ifndef A32_DIAG_H
#define A32_DIAG_H
#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
int a32_control(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a32_candidate(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
void *a32_scratch(void);
#endif
