"""Mechanical copies with one explicit stride1 row-window prefetch insertion."""
from pathlib import Path
import argparse,hashlib,json
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
r=Path(__file__).resolve().parents[3];d=Path(__file__).resolve().parent
raw=(r/'sw/yolo_fixed/dw3x3_rolling.h').read_bytes();original=raw.decode().replace('\r\n','\n')
fast='''#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
                if(!(((uintptr_t)r0|(uintptr_t)r1|(uintptr_t)r2)&3u)){
                    /* Four outputs need new columns3..6. Each aligned read
                     * covers columns4..7 and must remain inside its row.
                     * Prepack columns3..6, then keep the original per-pixel
                     * MMIO/quantization and 24-bit rolling-window format. */
                    uint32_t x=ox-l->pad;
                    while(last-ox>=4u && l->iw-x>=8u){
                        uint32_t n0=(a86_load4(r0+4)<<8)|(uint8_t)r0[3];
                        uint32_t n1=(a86_load4(r1+4)<<8)|(uint8_t)r1[3];
                        uint32_t n2=(a86_load4(r2+4)<<8)|(uint8_t)r2[3];
#ifdef YOLO_HOST_TEST
                        ++a86_word_batches;
#endif
                        for(uint32_t k=0;k<4;++k){
                            dest[ox++]=a86_candidate_dw3_quant(a86_candidate_dw3_dot(a,b,c),mult,bias,l->leaky);
                            a=(a>>8)|((n0&255u)<<16);n0>>=8;
                            b=(b>>8)|((n1&255u)<<16);n1>>=8;
                            c=(c>>8)|((n2&255u)<<16);n2>>=8;
                        }
                        r0+=4;r1+=4;r2+=4;x+=4;
                    }
                }
#endif
                if(ox<last)
'''
hashes={}
for variant in ['placebo','candidate']:
 s=original.replace('YOLO_DW3X3_ROLLING_H','A86_'+variant.upper()+'_ROLLING_H').replace('conv3x3_rolling','a86_'+variant+'_rolling').replace('dw3_','a86_'+variant+'_dw3_').replace('"../common/ai_mac_block.h"','"../../common/ai_mac_block.h"')
 if variant=='candidate':
  marker='            if(s==1){\n                for(;;){'
  assert s.count(marker)==1
  s=s.replace(marker,'            if(s==1){\n'+fast+'                for(;;){')
  marker='__attribute__((noinline)) static int a86_candidate_rolling('
  assert s.count(marker)==1
  helper='''#ifdef YOLO_HOST_TEST
static uint32_t a86_word_batches;
void a86_check_load4(const int8_t *p);
#endif
static inline uint32_t a86_load4(const int8_t *p){
#ifdef YOLO_HOST_TEST
 a86_check_load4(p);
#endif
 uint32_t v;__builtin_memcpy(&v,__builtin_assume_aligned(p,4),4);return v;}
'''
  s=s.replace(marker,helper+marker)
 path=d/f'{variant}_rolling.h'
 if a.check:assert path.read_text()==s
 else:path.write_text(s,encoding='utf-8',newline='\n')
 hashes[path.name]=hashlib.sha256(s.encode()).hexdigest().upper()
print(json.dumps(dict(result='A86_MECHANICAL_NAMESPACE_PLUS_WORD_PREFETCH_ONLY_PASS',production_header_sha256=hashlib.sha256(raw).hexdigest().upper(),headers=hashes)))
