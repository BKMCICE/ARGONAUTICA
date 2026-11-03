#define main a19_unused_profile_main
#define YOLO_LAYER_PROFILE 1
#define YOLO_BLOCK_PHASE_PROFILE 1
#define YOLO_BLOCK_CACHE_PHASE_PROFILE 1
#include "../../yolo_fixed/main.c"
#undef main
#include "diag.h"
int a19_profile(const YoloLayer *l,const int8_t *x,int8_t *y,const int8_t *w,const int32_t *p){
 block_phase_index=0;block_phase_stats[0]=(BlockPhaseStat){0};
 return conv1x1_block(l,x,y,w,p,l->ic/l->groups,l->oc/l->groups);
}
void a19_stats(A19Stats *out){
 const BlockPhaseStat *s=&block_phase_stats[0];
 for(unsigned i=0;i<6;++i)out->phase[i]=s->phase[i];
#define COPY(n) out->n=s->n
 COPY(weight_cycles);COPY(task_cycles);COPY(engine_cycles);COPY(cache_cycles);
 COPY(tasks);COPY(samples);COPY(batches);COPY(weight_words);COPY(vectors);COPY(input_words);
 COPY(result_words);COPY(polls);COPY(dots);COPY(max_task);
#undef COPY
}
