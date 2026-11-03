"""Reverse-prove exact production copies except one packed store loop."""
from pathlib import Path
import argparse,hashlib,json
r=Path(__file__).resolve().parents[3];here=Path(__file__).resolve().parent
def generated():
 source=r/'sw/yolo_fixed/main.c';text=source.read_text()
 binding=json.loads((r/'docs/validation/20261024-a75-dw5-pack-production/source_binding.json').read_text())['source_files']['sw/yolo_fixed/main.c']
 assert text==(r/binding['frozen_path']).read_text(),'Production source changed: re-review required'
 start=text.index('__attribute__((noinline)) static int conv1x1_block(')
 end=text.index('\n}\n#endif\n\nstatic const int8_t *output_of',start)+2;fn=text[start:end]+'\n'
 old='''                                for (uint32_t byte = 0; byte < count; ++byte) {
                                    dest[p++] = (int8_t)word;
                                    word >>= 8;
                                }'''
 new='''                                a79_store(dest+p,word,count);
                                p+=count;'''
 assert fn.count(old)==1
 placebo=fn.replace('static int conv1x1_block(','static int a79_placebo_block(')
 candidate=fn.replace('static int conv1x1_block(','static int a79_word_block(').replace(old,new)
 assert placebo.replace('static int a79_placebo_block(','static int conv1x1_block(')==fn
 assert candidate.replace('static int a79_word_block(','static int conv1x1_block(').replace(new,old)==fn
 return '/* Generated exact body, only function namespace and one store loop. */\n'+placebo+'\n'+candidate
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args();body=generated();dest=here/'candidate.inc'
 if a.check:assert dest.read_text()==body
 else:dest.write_text(body,encoding='utf-8',newline='\n')
 print('A79_ONLY_STORE_LOOP_CHANGE_AND_NAMESPACE_PLACEBO_PASS',hashlib.sha256(body.encode()).hexdigest().upper())
