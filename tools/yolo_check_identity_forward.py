"""Bind A71 forwarding to the reviewed fixed graph, producers and alias plan.

--check is mandatory in a forward-enabled Make build; it never updates inputs.
--write explicitly refreshes the contract/header after a source-level review.
This certificate is not a theorem for arbitrary C/RTL or hardware faults.
"""
import argparse,hashlib,json,re
from pathlib import Path
import yolo_plan_identity_arena as planner

def sha(path):return hashlib.sha256(path.read_bytes().replace(b'\r\n',b'\n')).hexdigest().upper()

def reviewed_files(root):
    names=['tools/yolo_plan_identity_arena.py','sw/yolo_fixed/main.c',
           'rtl/periph/ai_q24_post.v','rtl/periph/ai_conv3x3_quant8.v']
    names += [p.relative_to(root).as_posix() for folder in ['sw/common','sw/yolo_fixed']
              for p in (root/folder).glob('*.h')
              if p.name not in ['model_arena.h','model_identity_arena.h']]
    return {n:sha(root/n) for n in sorted(set(names))}

def proposal(root):
    graph=root/'sw/yolo_fixed/model_graph.h';layers,digest=planner.read_graph(graph)
    plan=planner.build(layers);proof=planner.verify(layers,plan)
    # Only the fixed reviewed graph is supported. Shapes alone do not prove
    # that a producer clips; inspect the actual kernel/groups too.
    rows=[list(map(int,re.findall(r'-?\d+',line.split('/*')[0])))
          for line in graph.read_text(encoding='utf-8-sig').splitlines()
          if re.search(r'/\* layer \d+ \*/',line)]
    for i in plan['forwarded_layers']:
        producer=rows[i-1]
        if producer[0]!=1 or producer[7]!=1 or producer[9]!=1:
            raise ValueError('Unreviewed forwarding producer')
    if len(layers)!=131 or len(plan['forwarded_layers'])!=20:
        raise ValueError('Changed model needs a new domain review')
    contract=dict(schema=1,graph_sha256=digest,source_sha256=reviewed_files(root),
                  plan=plan,symbolic_check=proof,
                  domain='Successful reviewed convolution outputs clip to[-127,127]. Quant RTL identity must match the deployed hardware; unsupported IDs fall back to the reviewed C stores. Upstream errors abort before forwarding. Not valid for arbitrary INT8 or changed producers.',
                  scope='Default-off production proposal, not adoption, board evidence or a whole-program formal theorem.')
    header=planner.render_header(plan,digest)
    header=header.replace('/* Isolated A70 host proposal; production model_arena.h is untouched. */',
                          '/* Generated A71 layout; use only with the checked identity contract. */\n#ifndef YOLO_MODEL_IDENTITY_ARENA_H\n#define YOLO_MODEL_IDENTITY_ARENA_H')
    header=header.replace('#define YOLO_MODEL_ARENA_H\n','').replace('a70_forwarded','yolo_identity_forwarded')+'#endif\n'
    return contract,header

def verify(root):
    expected,header=proposal(root)
    path=root/'sw/yolo_fixed'
    actual=json.loads((path/'identity_forward_contract.json').read_text(encoding='utf-8-sig'))
    if actual!=expected:raise ValueError('Identity contract stale: graph/source/domain/lifetimes require review')
    if (path/'model_identity_arena.h').read_text(encoding='ascii')!=header:
        raise ValueError('Identity arena header stale or unsafe')
    return expected

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,required=True)
    g=p.add_mutually_exclusive_group(required=True);g.add_argument('--check',action='store_true');g.add_argument('--write',action='store_true');a=p.parse_args();root=a.root.resolve()
    if a.write:
        contract,header=proposal(root);path=root/'sw/yolo_fixed'
        (path/'identity_forward_contract.json').write_text(json.dumps(contract,indent=2)+'\n',encoding='utf-8')
        (path/'model_identity_arena.h').write_text(header,encoding='ascii',newline='\n')
    result=verify(root)
    print('A71_IDENTITY_CONTRACT_PASS',result['graph_sha256'],result['plan']['arena_bytes'],len(result['plan']['forwarded_layers']))
if __name__=='__main__':main()
