"""Reject a saved placement recipe when its RTL/IP/constraints no longer match."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def validate(path):
    recipe = json.loads(path.read_text(encoding='utf-8-sig'))
    base = path.resolve().parent
    if recipe['profile'] != 'ddr' or not (0 <= recipe['hold_target_ps'] <= 200 and
                                        1 <= recipe['hold_iterations'] <= 100):
        raise ValueError('Unsupported placement recipe settings')
    inputs = json.loads((base / recipe['source_inputs']).read_text(encoding='utf-8-sig'))
    if inputs['functional_source_commit'] != recipe['functional_source_commit']:
        raise ValueError('Source revision binding mismatch')
    digest = lambda data: hashlib.sha256(data).hexdigest().upper()
    for name, entry in inputs['files'].items():
        raw = (ROOT / name).read_bytes()
        if digest(raw.replace(b'\r\n', b'\n')) != entry['normalized_sha256']:
            raise ValueError(f'Placement is bound to different source bytes: {name}')
    pcf = base / recipe['placement_pcf']
    if digest(pcf.read_bytes()) != recipe['placement_pcf_sha256']:
        raise ValueError('Saved placement constraint hash mismatch')
    return len(inputs['files'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recipe', type=Path)
    args = parser.parse_args()
    print(f'PDS_RECIPE_PASS source_inputs={validate(args.recipe)}')
