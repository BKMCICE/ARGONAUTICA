"""Recompute the18 actual-size paired measurements from raw UART/simulator text."""
import argparse,json,re
from pathlib import Path
def summarize(text,cases):
    if text.count('A65_SHORTCUT_PASS')!=1 or 'A65_SHORTCUT_FAIL' in text or '[TRAP]' in text:
        raise ValueError('Missing completion or firmware error')
    if text.count('TCM_STACK finish sp=0x0000ffe0 guard_changed_words=0 main_return=0x00000000 guard=PASS')!=1:
        raise ValueError('Stack/return verification incomplete')
    rows=[dict(layer=int(m[1]),count=int(m[2]),sample=int(m[3]),control=int(m[4],16),candidate=int(m[5],16))
          for m in re.finditer(r'A65_SAMPLE layer=(\d+) count=(\d+) sample=(\d+) control=0x([0-9a-f]+) candidate=0x([0-9a-f]+)',text)]
    if len(rows)!=54:raise ValueError('Need18 shapes, three paired samples each')
    output=[]
    for case in cases:
        samples=[x for x in rows if x['layer']==case['layer']]
        if sorted(x['sample'] for x in samples)!=[0,1,2] or any(x['count']!=case['count'] or min(x['control'],x['candidate'])<=0 for x in samples):
            raise ValueError('Missing/duplicate/wrong-size sample')
        control=sum(x['control'] for x in samples)/3;candidate=sum(x['candidate'] for x in samples)/3
        output.append(dict(layer=case['layer'],count=case['count'],control_mean_cycles=control,candidate_mean_cycles=candidate,
            reduction_percent=100*(1-candidate/control),samples=samples))
    control=sum(x['control_mean_cycles'] for x in output);candidate=sum(x['candidate_mean_cycles'] for x in output)
    return dict(result='PASS',cases=output,control_sum_mean_cycles=control,candidate_sum_mean_cycles=candidate,
                aggregate_reduction_percent=100*(1-candidate/control),all_shapes_faster=all(x['candidate_mean_cycles']<x['control_mean_cycles'] for x in output),
                scope='One complete isolated function per actual shape, includes per-call LUT construction. Predetermined mixed signed inputs; not real network activations, whole YOLO time, or AP. CSR/call overhead common to both paths.')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('log',type=Path);p.add_argument('--generated',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    result=summarize(a.log.read_bytes().decode('ascii').replace('\r',''),json.loads((a.generated/'generation.json').read_text())['cases'])
    a.output.write_text(json.dumps(result,indent=2)+'\n');print(result['aggregate_reduction_percent'],result['all_shapes_faster'])
