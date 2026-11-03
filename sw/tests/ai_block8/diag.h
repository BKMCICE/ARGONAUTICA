#ifndef A33_DIAG_H
#define A33_DIAG_H
#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
int a33_control(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a33_candidate(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
void *a33_scratch(void);
#endif
