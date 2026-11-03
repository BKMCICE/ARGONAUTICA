"""A78 post8-only phase records: eight outputs, packed reads, exact sampling counts.

Raw wire field q24 is post-read/unpack/store in this compiled post8 path;
wire read stays zero. No claim of CPU Q24 timing, stalls or unbiased attribution.
"""
import argparse,hashlib,json,re
from pathlib import Path
from summarize_yolo_layers import read_graph,summarize as summarize_layers

COUNTS=('index','tasks','samples','batches','wwords','vectors','iwords','rwords','polls','dots','max_task')
CYCLES=('cache','weight','setup','pack','write','wait','read','q24','task','engine')
WIRE_PHASES=('setup','pack','write','wait','read','q24')
NAMES={'setup':'setup','pack':'pack_uncached','write':'pixel_submit','wait':'submit_wait_including_quant','read':'unused_wire_read','q24':'post_read_unpack_store'}
def require(ok,message):
 if not ok:raise ValueError(message)

def expected_shapes(text):
 rows={}
 for line in text.splitlines():
  m=re.search(r'/\* layer (\d+) \*/',line)
  if not m:continue
  v=list(map(int,re.findall(r'-?\d+',line.split('/*')[0])));require(len(v)==25,'Invalid graph row')
  kind,ih,iw,ic,oh,ow,oc,k,stride,g,pad=v[:11]
  if kind!=1 or k!=1:continue
  require(g>0 and ic%g==0 and oc%g==0 and pad==0 and min(ih,iw,oh,ow,stride)>0,'Invalid block shape')
  ci,co=ic//g,oc//g;blocks=(ci+8)//9
  require(0<ci<=224 and (oh-1)<=(ih-1)//stride and (ow-1)<=(iw-1)//stride,'Unsupported geometry')
  cached=co>4 and oh*ow<=76800//(blocks*3)
  e=dict(index=int(m[1]),tasks=0,samples=0,batches=0,wwords=0,vectors=0,iwords=0,rwords=0,dots=0)
  for _ in range(g):
   for base in range(0,co,8):
    outputs=min(8,co-base);e['batches']+=1;e['wwords']+=outputs*blocks*3
    for y in range(oh):
     for x in range(0,ow,8):
      pixels=min(8,ow-x);take=e['tasks']%64==0 or (y+1==oh and x+pixels==ow and base+outputs==co);e['tasks']+=1
      if take:
       e['samples']+=1;e['vectors']+=blocks*pixels;e['iwords']+=blocks*pixels*3
       e['rwords']+=outputs*((pixels+3)//4);e['dots']+=blocks*outputs*pixels
  rows[e['index']]=dict(expected=e,cached=cached,groups=g,input_channels=ci,output_channels=co,blocks=blocks,pixels=oh*ow,path='cached_small' if cached and ci<=9 else 'cached_wide' if cached else 'uncached_small')
 return rows

def summarize(raw,graph_path):
 graph,gsha=read_graph(graph_path);layer=summarize_layers(raw,graph,100000000)
 expected=expected_shapes(graph_path.read_text(encoding='utf-8-sig'));lines=raw.decode('ascii').replace('\r','').splitlines()
 headers=[x for x in lines if x.startswith('YOLO_BLOCK_PHASE_BEGIN')]
 require(len(headers)==1 and lines.count('YOLO_BLOCK_PHASE_END')==1,'Missing/repeated phase envelope')
 h=re.fullmatch(r'YOLO_BLOCK_PHASE_BEGIN stride=64 tail=group_last clock_bits=32 calibration_min=(\d+) calibration_max=(\d+)',headers[0]);require(h,'Bad phase header')
 low,high=map(int,h.groups());require(0<low<=high<1000000,'Invalid CSR calibration')
 begin,end=lines.index(headers[0]),lines.index('YOLO_BLOCK_PHASE_END');require(begin<end,'Reversed envelope')
 records=lines[begin+1:end];require(len(records)==len(expected),'Wrong row count')
 require(sum(x.startswith('YOLO_BLOCK_PHASE ') for x in lines)==len(expected),'Phase row outside envelope')
 pattern='YOLO_BLOCK_PHASE '+' '.join(k+r'=(\d+)' for k in COUNTS)+''.join(' '+k+r'=0x([0-9a-f]{16})' for k in CYCLES)
 rows=[]
 for text in records:
  match=re.fullmatch(pattern,text);require(match,'Malformed phase row');values=match.groups()
  row=dict(zip(COUNTS,map(int,values[:len(COUNTS)])));row.update(zip(CYCLES,(int(x,16) for x in values[len(COUNTS):])))
  require(row['index'] in expected and row['index'] not in [x['index'] for x in rows],'Unexpected/repeated layer')
  shape=expected[row['index']];require(all(row[k]==v for k,v in shape['expected'].items()),'Eight-output sampling/packed transfer/dot count mismatch')
  require(row['samples']<=row['polls']<=row['samples']*100000,'Poll count out of bounds')
  require(row['engine']==3*row['dots'] and 0<row['engine']<=row['wait'],'Block8 MAC counter/wait mismatch')
  require(0<row['max_task']<2**31 and 0<row['task']<=row['max_task']*row['samples'],'Invalid task interval')
  require(row['read']==0,'Post8 wire read must be zero; it is not the packed-read window')
  require((row['pack']==0 and row['cache']>0) if shape['cached'] else (row['pack']>0 and row['cache']==0),'Cache/pack path mismatch')
  require(all(row[k]>0 for k in ['weight','setup','write','wait','q24']),'Empty required interval')
  phases=sum(row[k] for k in WIRE_PHASES);require(phases<=row['task'],'Overlapping/excess phase windows')
  lc=layer['layers'][row['index']]['cycles'];require(row['task']+row['weight']+row['cache']<lc,'Subset and full-pass windows exceed layer')
  row.update(cached=shape['cached'],path=shape['path'],input_channels=shape['input_channels'],output_channels=shape['output_channels'],layer_cycles=lc,remainder_cycles=row['task']-phases,
    phase_percent_of_sampled_task={NAMES[k]:row[k]/row['task']*100 for k in WIRE_PHASES},cache_percent_of_instrumented_layer=row['cache']/lc*100,weight_percent_of_instrumented_layer=row['weight']/lc*100)
  rows.append(row)
 require([x['index'] for x in rows]==sorted(expected),'Rows out of order')
 return dict(result='YOLO_POST8_CACHED_PHASE_PASS',uart_sha256=hashlib.sha256(raw).hexdigest().upper(),graph_sha256=gsha,nominal_hz=100000000,forward_cycles=layer['forward_cycles'],calibration_min=low,calibration_max=high,layers=rows,
  semantics=NAMES,scope='Pinned A61 A481 post8 path only. First/every64th plus group-last deterministic task samples; cache/weight cover all groups/batches. Wire q24 means packed read/unpack/store, read=0; no CPU Q24 window. Engine is overlapping raw MAC cycles within submit/wait, excludes postprocessor costs and cannot be added again. Raw instrumentation/calibration retained, no subtraction/extrapolated full-layer attribution, bus-stall proof, engine utilization, AP or new formal speed. Low32 intervals assume <2^32; observed max is not a universal bound.')

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('uart',type=Path);p.add_argument('--graph',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 out=summarize(a.uart.read_bytes(),a.graph);a.output.write_text(json.dumps(out,indent=2)+'\n');print(out['result'],len(out['layers']))
if __name__=='__main__':main()
