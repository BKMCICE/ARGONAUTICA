"""Isolated identity forwarding plan; never updates the production arena header."""
import argparse,copy,hashlib,json,re
from pathlib import Path


def require(ok,message):
    if not ok:raise ValueError(message)


def read_graph(path):
    text=path.read_text(encoding='utf-8-sig').replace('\r\n','\n')
    count=int(re.search(r'#define YOLO_LAYER_COUNT (\d+)',text)[1]);layers=[]
    for line in text.splitlines():
        match=re.search(r'/\* layer (\d+) \*/',line)
        if not match:continue
        v=list(map(int,re.findall(r'-?\d+',line.split('/*')[0])))
        require(len(v)==25 and int(match[1])==len(layers),'Malformed graph row')
        require(v[0] in range(1,8) and 0<=v[21]<=4,'Bad kind/source count')
        require(all(x>0 for x in v[1:7]),'Empty tensor dimension')
        layers.append(dict(index=len(layers),kind=v[0],input_shape=v[1:4],shape=v[4:7],
                           bytes=v[4]*v[5]*v[6],sources=v[12:12+v[21]],q24=v[20]))
    require(len(layers)==count,'Incomplete graph')
    return layers,hashlib.sha256(text.encode()).hexdigest().upper()


def dependencies(layers):
    reads=[]
    for i,l in enumerate(layers):
        require(l['index']==i and l['kind'] in range(1,8) and l['bytes']>0,'Invalid layer')
        if l['kind']==2:
            require(bool(l['sources']),'Route has no inputs');sources=list(l['sources'])
        else:
            sources=[i-1] if i else []
            if l['kind']==3:
                require(len(l['sources'])==1,'Shortcut source count');sources+=l['sources']
        require(all(0<=x<i for x in sources),'Noncausal edge')
        reads.append(sources)
    return reads


def eligible(layers,i):
    l=layers[i]
    return (i>0 and l['kind'] in [6,7] and l['q24']==16777216 and
            layers[i-1]['kind']==1 and l['shape']==l['input_shape']==layers[i-1]['shape'])


def aligned(n,a):return (n+a-1)//a*a


def build(layers,alignment=32):
    require(alignment>0 and alignment&(alignment-1)==0,'Alignment')
    reads=dependencies(layers);roots=[i-1 if eligible(layers,i) else i for i in range(len(layers))]
    # Eligibility intentionally only accepts a direct convolution producer;
    # no arbitrary raw image, nonunity multiplier or identity chain is folded.
    groups={i:dict(root=i,members=[],bytes=l['bytes'],last_use=i) for i,l in enumerate(layers) if roots[i]==i}
    for i,root in enumerate(roots):groups[root]['members'].append(i)
    for i,sources in enumerate(reads):
        for source in sources:groups[roots[source]]['last_use']=max(groups[roots[source]]['last_use'],i)
    heads=[i for i,l in enumerate(layers) if l['kind']==7]
    for i in heads:groups[roots[i]]['last_use']=len(layers)
    offsets=[];active=[];arena=peak=0
    for i,l in enumerate(layers):
        if roots[i]!=i:offsets.append(offsets[roots[i]]);continue
        active=[v for v in active if v[2]>=i]
        size=aligned(l['bytes'],alignment);offset=0
        for start,n,end in sorted(active):
            if offset+size<=start:break
            offset=max(offset,start+n)
        offsets.append(offset);active.append((offset,size,groups[i]['last_use']))
        arena=max(arena,offset+size);peak=max(peak,sum(v[1] for v in active))
    out=dict(result='ISOLATED_IDENTITY_PLAN',alignment=alignment,arena_bytes=arena,peak_live_padded_bytes=peak,
             offsets=offsets,roots=roots,groups=list(groups.values()),retained_heads=heads,
             forwarded_layers=[i for i in range(len(layers)) if roots[i]!=i],
             forwarded_tensor_bytes=sum(l['bytes'] for i,l in enumerate(layers) if roots[i]!=i),
             dependencies=reads,
             domain_contract='Only unity dropout/head immediately after a same-shaped convolution. Forwarding requires successful convolution outputs saturated to[-127,127]; not true for arbitrary INT8 including-128.',
             scope='Offline first-fit proposal with inclusive lifetimes, no in-place nonidentity writes. Does not update production header or prove target speed. Independent symbolic ownership check required.')
    verify(layers,out);return out


def verify(layers,plan):
    """Re-derive edges and last readers, then simulate32B ownership independently."""
    n=len(layers);a=plan['alignment'];require(a>0 and a&(a-1)==0,'Alignment')
    offsets=plan['offsets'];roots=plan['roots'];arena=plan['arena_bytes']
    require(len(offsets)==len(roots)==n and arena>0 and arena%a==0,'Plan size')
    require(roots==[i-1 if eligible(layers,i) else i for i in range(n)],'Invalid alias/root')
    reads=dependencies(layers);end=[i for i in range(n)]
    for i,refs in enumerate(reads):
        for j in refs:end[roots[j]]=max(end[roots[j]],i)
    heads=[i for i,l in enumerate(layers) if l['kind']==7]
    for i in heads:end[roots[i]]=n
    expected_groups=[]
    for i,l in enumerate(layers):
        require(type(offsets[i]) is int and offsets[i]>=0 and offsets[i]%a==0,'Offset alignment')
        require(offsets[i]+aligned(l['bytes'],a)<=arena,'Arena overflow')
        if roots[i]!=i:require(offsets[i]==offsets[roots[i]],'Forwarded offset changed')
        else:expected_groups.append(dict(root=i,members=[j for j in range(n) if roots[j]==i],bytes=l['bytes'],last_use=end[i]))
    require(plan['groups']==expected_groups and plan['dependencies']==reads,'Lifetime/edge certificate mismatch')
    require(plan['retained_heads']==heads,'Missing retained head')
    require(plan['forwarded_layers']==[i for i in range(n) if roots[i]!=i],'Forwarded list')
    require(plan['forwarded_tensor_bytes']==sum(layers[i]['bytes'] for i in plan['forwarded_layers']),'Byte count')
    owner=[-1]*(arena//a);operations=0
    def slots(i):return range(offsets[i]//a,(offsets[i]+aligned(layers[i]['bytes'],a))//a)
    def intact(i):return all(owner[k]==roots[i] for k in slots(i))
    for i in range(n):
        for source in reads[i]:require(intact(source),f'Input overwritten before consumer:{source}->{i}')
        if roots[i]==i:
            for k in slots(i):
                prior=owner[k]
                require(prior<0 or end[prior]<i,f'Live group overwritten:{prior}->{i}')
            for k in slots(i):owner[k]=i;operations+=1
        else:require(intact(i),'Alias producer is not intact')
        for j in range(i+1):
            if end[roots[j]]>=i:require(intact(j),f'Live value overwritten:{j} at{i}')
    for i in heads:require(intact(i),'Final head overwritten')
    return dict(result='SYMBOLIC_OWNERSHIP_PASS',writes_of_aligned_blocks=operations,retained_heads=heads,roots=len(expected_groups))


def render_header(plan,graph_sha):
    rows=['/* Isolated A70 host proposal; production model_arena.h is untouched. */',
          '#include "model_graph.h"','#define YOLO_MODEL_ARENA_H',
          f'#define YOLO_COMPACT_ACTIVATION_BYTES {plan["arena_bytes"]}u',
          f'#define YOLO_ARENA_GRAPH_SHA256 "{graph_sha}"',
          'static const uint32_t yolo_compact_offsets[YOLO_LAYER_COUNT] = {']
    rows+=['  '+','.join(str(x)+'u' for x in plan['offsets'][i:i+8])+',' for i in range(0,len(plan['offsets']),8)]
    rows+=['};','static const unsigned char a70_forwarded[YOLO_LAYER_COUNT] = {',
           ','.join('1' if i in plan['forwarded_layers'] else '0' for i in range(len(plan['roots']))),'};','']
    return '\n'.join(rows)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--graph',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--header',type=Path,required=True);args=p.parse_args()
    layers,digest=read_graph(args.graph);result=build(layers);result['symbolic_check']=verify(layers,result);result['normalized_model_graph_sha256']=digest
    args.output.parent.mkdir(exist_ok=True,parents=True);args.header.write_text(render_header(result,digest),encoding='ascii',newline='\n')
    args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print('A70_IDENTITY_PLAN_PASS',result['arena_bytes'],len(result['forwarded_layers']),result['forwarded_tensor_bytes'])
if __name__=='__main__':main()
