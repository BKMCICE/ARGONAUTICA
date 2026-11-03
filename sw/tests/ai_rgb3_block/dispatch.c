/* A25 host tests exercise the actual production dispatcher, including a
 * timeout after one successful tile. No target image includes this file. */
#ifndef YOLO_HOST_TEST
#error "dispatch.c is host-only"
#endif
#if !YOLO_RGB3_BLOCK
#error "dispatch.c requires YOLO_RGB3_BLOCK=1"
#endif
#include <stdio.h>
#include <string.h>
#include "../ai_1x1_block_layer/host_mmio.h"
#define main a25_unused_production_main
#include "../../yolo_fixed/main.c"
#undef main
uint32_t host_ai_calls;
static int8_t in[6*5*7],out[6*5*7+16],ref[6*5*7+16];
static void init(void){for(unsigned i=0;i<sizeof(in);++i)in[i]=(int8_t)(i*73+19);memset(out,0x5a,sizeof(out));memset(ref,0x5a,sizeof(ref));host_ai_calls=0;}
static int compare(YoloLayer l,unsigned mode,unsigned block)
{
 init();a03_reset(mode);
 conv3x3_input3_prepacked(&l,in,ref+8,yolo_weights,yolo_params_q24,l.oc/l.groups);
 host_ai_calls=0;
 if(!conv_layer(&l,in,out+8)||memcmp(out,ref,sizeof(out)))return 1;
 if(block?(!a03_starts||!a03_weight_words||!a03_pixel_words):a03_starts||a03_writes)return 2;
 return 0;
}
int main(void)
{
 YoloLayer l=yolo_layers[0];l.ih=5;l.iw=7;l.oh=5;l.ow=7;l.ic=3;l.oc=5;l.size=3;l.groups=1;l.stride=1;l.pad=1;l.weight_offset=l.param_offset=0;
 if(compare(l,0,1)||compare(l,1,0))return 10;
 YoloLayer tiny=l;tiny.oh=tiny.ow=1;
 if(compare(tiny,0,0)||a03_reads)return 11;
 YoloLayer grouped=l;grouped.groups=2;grouped.ic=6;grouped.oc=6;
 if(compare(grouped,0,0)||a03_reads)return 12;
 for(unsigned mode=2;mode<=6;++mode){
  init();a03_reset(mode);
  if(conv_layer(&l,in,out+8))return 13;
  /* Only successful block work increments host_ai_calls. Legacy fallback
   * would recompute 525 scalar calls, which is forbidden after an error. */
  unsigned expected=mode==5||mode==6?4*7*3:0;
  if(host_ai_calls!=expected||a03_starts!=(mode==2?0:mode==6?2:1))return 14;
  if(mode==6){
   unsigned changed=0;for(unsigned i=8;i<8+l.oh*l.ow*l.oc;++i)changed+=out[i]!=0x5a;
   if(!changed||changed>4*7)return 15;
  }
  for(unsigned i=0;i<sizeof(out);++i)if((i<8||i>=8+l.oh*l.ow*l.oc)&&out[i]!=0x5a)return 16;
 }
 init();a03_reset(0);l.oc=0;
 if(conv_layer(&l,in,out+8)||a03_reads||a03_writes)return 17;
 puts("A25_PRODUCTION_DISPATCH_PASS normal=1 old_id=1 tiny=1 grouped=1 errors=5 partial_timeout=1 bad_shape=1");return 0;
}
