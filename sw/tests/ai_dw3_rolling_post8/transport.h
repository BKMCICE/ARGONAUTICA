#ifndef A89_TRANSPORT_H
#define A89_TRANSPORT_H
#ifdef YOLO_HOST_TEST
#include "../../common/soc.h"
uint32_t a89_read(uint32_t);
void a89_write(uint32_t,uint32_t);
#define AI_BLOCK_READ(off) a89_read(off)
#define AI_BLOCK_WRITE(off,v) a89_write(off,v)
/* Fixture-only hooks: retain the production packers and resident weights;
 * replace mathematical host dot with legacy MMIO on the actual RTL. */
#include "../../common/ai_mac.h"
int32_t a89_rtl_dot(uint32_t,uint32_t,uint32_t,uint32_t,uint32_t,uint32_t);
void a89_rtl_weights(uint32_t,uint32_t,uint32_t);
#define ai_dot9_packed a89_rtl_dot
#define ai_load_1x1_weights a89_saved_load
#include "../../common/ai_mac_reuse.h"
#undef ai_load_1x1_weights
static inline void ai_load_1x1_weights(const int8_t *p,uint32_t n){
 a89_saved_load(p,n);a89_rtl_weights(host_resident_weights[0],host_resident_weights[1],host_resident_weights[2]);
}
#endif
#endif
