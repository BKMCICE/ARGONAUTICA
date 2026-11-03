"""Inspect a Darknet YOLO cfg/weights pair for the RV32 model port.

Records layer shapes and the float offsets of convolution parameters. This is
an inventory tool, not an inference engine or a quantizer.
"""
import argparse
import json
import struct
from pathlib import Path


def parse_cfg(path: Path) -> list[dict[str, str]]:
    sections: list[dict[str, str]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            sections.append({"type": line[1:-1]})
        else:
            key, value = line.split("=", 1)
            sections[-1][key.strip()] = value.strip()
    if not sections or sections[0]["type"] != "net":
        raise ValueError("first cfg section must be [net]")
    return sections


def manifest(cfg: Path, weights: Path) -> dict:
    sections = parse_cfg(cfg)
    data = weights.read_bytes()
    major, minor, revision = struct.unpack_from("<3i", data)
    if (major, minor) != (0, 2):
        raise ValueError(f"unsupported Darknet weights header {(major, minor, revision)}")
    seen = struct.unpack_from("<Q", data, 12)[0]
    if (len(data) - 20) % 4:
        raise ValueError("weights size is not a whole number of float32 values")
    input_shape = [int(sections[0][k]) for k in ("height", "width", "channels")]
    shapes: list[list[int]] = []
    layers: list[dict] = []
    float_offset = 0
    for idx, sec in enumerate(sections[1:]):
        kind = sec["type"]
        h, w, c = shapes[-1] if shapes else input_shape
        entry: dict = {"index": idx, "type": kind}
        if kind == "convolutional":
            filters = int(sec["filters"])
            size = int(sec["size"])
            stride = int(sec.get("stride", 1))
            groups = int(sec.get("groups", 1))
            if c % groups or filters % groups:
                raise ValueError(f"layer {idx}: invalid groups {groups}")
            pad = size // 2 if int(sec.get("pad", 0)) else int(sec.get("padding", 0))
            out_shape = [(h + 2 * pad - size) // stride + 1,
                         (w + 2 * pad - size) // stride + 1, filters]
            count = filters * (c // groups) * size * size
            bn = int(sec.get("batch_normalize", 0)) != 0
            total = count + filters * (4 if bn else 1)
            entry.update({"input": [h, w, c], "shape": out_shape,
                          "size": size, "stride": stride, "groups": groups,
                          "activation": sec.get("activation", "linear"),
                          "batch_norm": bn, "float_offset": float_offset,
                          "float_count": total})
            float_offset += total
        elif kind == "route":
            refs = [int(x) for x in sec["layers"].split(",")]
            indices = [idx + x if x < 0 else x for x in refs]
            selected = [shapes[x] for x in indices]
            if any(s[:2] != selected[0][:2] for s in selected):
                raise ValueError(f"layer {idx}: route spatial dimensions differ")
            out_shape = [*selected[0][:2], sum(s[2] for s in selected)]
            entry.update({"sources": indices, "shape": out_shape})
        elif kind == "shortcut":
            ref = int(sec["from"])
            source = idx + ref if ref < 0 else ref
            if shapes[source] != [h, w, c]:
                raise ValueError(f"layer {idx}: shortcut shape differs")
            out_shape = [h, w, c]
            entry.update({"source": source, "shape": out_shape})
        elif kind == "maxpool":
            size = int(sec["size"])
            stride = int(sec["stride"])
            # Darknet maxpool uses size-1 total padding for same resolution at stride 1.
            out_shape = [(h + size - 1 - size) // stride + 1,
                         (w + size - 1 - size) // stride + 1, c]
            entry.update({"size": size, "stride": stride, "shape": out_shape})
        elif kind == "upsample":
            stride = int(sec["stride"])
            out_shape = [h * stride, w * stride, c]
            entry.update({"stride": stride, "shape": out_shape})
        elif kind in ("dropout", "yolo"):
            out_shape = [h, w, c]
            entry["shape"] = out_shape
        else:
            raise ValueError(f"unsupported layer type {kind} at {idx}")
        shapes.append(out_shape)
        layers.append(entry)
    expected = (len(data) - 20) // 4
    if float_offset != expected:
        raise ValueError(f"weights count mismatch: cfg={float_offset}, file={expected}")
    return {"header": {"major": major, "minor": minor, "revision": revision,
                       "seen": seen}, "input_shape": input_shape,
            "float_count": expected, "layers": layers}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("cfg", type=Path)
    ap.add_argument("weights", type=Path)
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()
    result = manifest(args.cfg, args.weights)
    summary = {kind: sum(x["type"] == kind for x in result["layers"])
               for kind in sorted({x["type"] for x in result["layers"]})}
    print(f"layers={len(result['layers'])} weights={result['float_count']} "
          f"input={result['input_shape']} types={summary}")
    if args.output:
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n",
                               encoding="utf-8")


if __name__ == "__main__":
    main()
