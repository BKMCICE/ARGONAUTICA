#ifndef A48_DIAG_H
#define A48_DIAG_H
#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
int a48_control(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a48_candidate(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
void *a48_scratch(void);
#endif
