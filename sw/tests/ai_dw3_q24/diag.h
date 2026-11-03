#ifndef A30_DIAG_H
#define A30_DIAG_H
#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
int a30_control(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a30_placebo(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a30_candidate(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int64_t a30_wide_scale(int32_t,int32_t);
int32_t a30_old_scale(int32_t,int32_t);
int32_t a30_scale(int32_t,int32_t);
int8_t a30_quant(int32_t,int32_t,int32_t,uint32_t);
int8_t a30_old_quant(int32_t,int32_t,int32_t,uint32_t);
#endif
