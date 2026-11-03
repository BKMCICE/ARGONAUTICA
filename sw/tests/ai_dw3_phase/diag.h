#ifndef A29_DIAG_H
#define A29_DIAG_H
#include "soc.h"
#include "../../yolo_fixed/model_graph.h"
enum { A29_PACK, A29_WRITE, A29_WAIT, A29_READ, A29_Q24, A29_ADVANCE, A29_PHASES };
typedef struct {
    uint64_t phase[A29_PHASES],weight,seed,border;
    uint32_t interior,boundary,samples,updates,seeds,weights,polls;
} A29Stats;
int a29_control(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
int a29_profile(const YoloLayer *,const int8_t *,int8_t *,const int8_t *,const int32_t *);
void a29_stats(A29Stats *);
uint64_t a29_clock_overhead(void);
#endif
