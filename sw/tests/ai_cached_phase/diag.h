#ifndef A19_DIAG_H
#define A19_DIAG_H
#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
typedef struct {
 uint64_t phase[6],weight_cycles,task_cycles,engine_cycles,cache_cycles;
 uint32_t tasks,samples,batches,weight_words,vectors,input_words,result_words,polls,dots,max_task;
} A19Stats;
int a19_control(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a19_profile(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
void a19_stats(A19Stats *);
#endif
