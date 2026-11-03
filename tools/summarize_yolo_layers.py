"""Validate and summarize target YOLO_LAYER_PROFILE logs for the fixed dog test."""
import argparse
import hashlib
import json
import re
from pathlib import Path


KINDS = {1: "conv", 2: "route", 3: "shortcut", 4: "maxpool",
         5: "upsample", 6: "dropout", 7: "head"}
EXPECTED_DETECTIONS = [
    "car 844/1000 [188,45,281,94]", "dog 701/1000 [52,118,152,285]",
    "car 423/1000 [287,64,305,87]", "bicycle 403/1000 [105,101,247,241]",
    "person 370/1000 [26,42,45,65]", "bicycle 316/1000 [36,104,179,271]",
]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_graph(path):
    raw = path.read_bytes()
    text = raw.decode("utf-8-sig")
    count = int(re.search(r"#define YOLO_LAYER_COUNT (\d+)", text)[1])
    graph = []
    for line in text.splitlines():
        match = re.search(r"/\* layer (\d+) \*/", line)
        if not match:
            continue
        fields = [int(v) for v in re.findall(r"-?\d+", line.split("/*")[0])]
        require(int(match[1]) == len(graph), "Non-sequential graph layer")
        require(len(fields) >= 12 and fields[0] in KINDS, "Invalid graph row")
        graph.append({"index": len(graph), "kind": fields[0], "kernel": fields[7],
                      "input_channels": fields[3], "output_channels": fields[6],
                      "groups": fields[9]})
    require(len(graph) == count, "Incomplete model graph")
    return graph, hashlib.sha256(raw).hexdigest().upper()


def summarize(raw, graph, nominal_hz):
    require(nominal_hz > 0, "Nominal frequency must be positive")
    lines = raw.decode("ascii").replace("\r", "").splitlines()
    for marker in ["RV32BOOT1", "GO", "YOLO_FIXED START", "YOLO_INPUT 307200",
                   "YOLO_INPUT_OK", "YOLO_FIXED HEADS 99860b0f 98155281",
                   "YOLO_FIXED PASS", "detections=6",
                   f"YOLO_PROFILE_BEGIN layers={len(graph)}", "YOLO_PROFILE_END"]:
        require(lines.count(marker) == 1, f"Missing or repeated marker: {marker}")
    require(not any(word in raw for word in [b"[TRAP]", b"HASH FAIL", b"BAD HASH",
                                             b"YOLO_INPUT_BAD", b"TCM_TEXT_FAIL",
                                             b"TCM_STACK_FAIL", b"guard=FAIL",
                                             b"YOLO_TCM_LAYER_FAIL", b"AI_DW3X3_REUSE_FAIL"]),
            "Firmware failure marker")
    detections = [s for s in lines if re.fullmatch(r"\w+ \d+/1000 \[\d+,\d+,\d+,\d+\]", s)]
    require(detections == EXPECTED_DETECTIONS, "Fixed dog detections differ")
    totals = [s for s in lines if s.startswith("YOLO_FORWARD_CYCLES=")]
    require(len(totals) == 1 and re.fullmatch(r"YOLO_FORWARD_CYCLES=0x[0-9a-f]{16}", totals[0]),
            "Invalid forward cycle total")
    total = int(totals[0].split("=")[1], 16)
    require(0 < total < 2**64, "Invalid forward cycle range")
    begin, end = lines.index(f"YOLO_PROFILE_BEGIN layers={len(graph)}"), lines.index("YOLO_PROFILE_END")
    require(lines.index(totals[0]) < begin < end, "Profile must follow the forward total")
    stack = None
    if any(line.startswith("TCM_STACK") for line in lines):
        starts = [line for line in lines if line.startswith("TCM_STACK begin")]
        finishes = [line for line in lines if line.startswith("TCM_STACK finish")]
        require(len(starts) == len(finishes) == 1, "Incomplete/repeated TCM stack checks")
        first = re.fullmatch(r"TCM_STACK begin bottom=0x([0-9a-f]{8}) top=0x([0-9a-f]{8}) sp=0x([0-9a-f]{8}) guard_bytes=(\d+)", starts[0])
        last = re.fullmatch(r"TCM_STACK finish sp=0x([0-9a-f]{8}) guard_changed_words=(\d+) main_return=0x([0-9a-f]{8}) guard=PASS", finishes[0])
        require(first is not None and last is not None, "Malformed TCM stack checks")
        bottom, top, entry_sp = (int(first[i], 16) for i in (1, 2, 3))
        require((bottom, top, int(first[4])) == (0xe000, 0x10000, 256), "Unexpected TCM stack reservation")
        require(0xe100 <= entry_sp < top and 0xe100 <= int(last[1], 16) < top,
                "TCM stack pointer outside usable region")
        require(int(last[2]) == 0 and int(last[3], 16) == 0, "TCM stack guard/return failure")
        require(lines.index(starts[0]) < lines.index("YOLO_FIXED START") < begin < end < lines.index(finishes[0]),
                "TCM stack checks do not bracket the complete inference/profile")
        stack = dict(result="TCM_STACK_COMPLETION_PASS", bottom=f"{bottom:08x}", top=f"{top:08x}",
                     entry_function_sp=first[3], finish_function_sp=last[1], guard_bytes=256,
                     guard_changed_words=0, main_return=0)
    rows = [s for s in lines if s.startswith("YOLO_LAYER ")]
    require(len(rows) == len(graph) and lines[begin + 1:end] == rows, "Incomplete profile block")
    layers, groups = [], {}
    for expected, row in zip(graph, rows):
        match = re.fullmatch(r"YOLO_LAYER index=(\d+) kind=(\d+) kernel=(\d+) cycles=0x([0-9a-f]{16})", row)
        require(match is not None, "Malformed layer row")
        index, kind, kernel = map(int, match.group(1, 2, 3))
        require((index, kind, kernel) == (expected['index'], expected['kind'], expected['kernel']),
                "Layer index/type/kernel differs from model graph")
        cycles = int(match[4], 16)
        require(0 < cycles <= total, "Invalid layer cycle range")
        name = f"conv{kernel}x{kernel}" if kind == 1 else KINDS[kind]
        if kind == 1 and expected['groups'] > 1:
            name += "_depthwise" if expected['groups'] == expected['input_channels'] else "_grouped"
        item = dict(expected, operator=name, cycles=cycles,
                    seconds_at_nominal_hz=cycles / nominal_hz,
                    percent_of_forward=100 * cycles / total)
        layers.append(item)
        group = groups.setdefault(name, {"layers": 0, "cycles": 0})
        group['layers'] += 1
        group['cycles'] += cycles
    measured = sum(item['cycles'] for item in layers)
    require(measured <= total, "Layer windows exceed total forward window")
    for group in groups.values():
        group.update(seconds_at_nominal_hz=group['cycles'] / nominal_hz,
                     percent_of_forward=100 * group['cycles'] / total)
    result = dict(result="YOLO_LAYER_PROFILE_PASS", nominal_hz=nominal_hz,
                frequency="Nominal; not independently measured",
                forward_cycles=total, forward_seconds_at_nominal_hz=total / nominal_hz,
                sampled_layer_cycles=measured, outside_layer_windows_cycles=total - measured,
                groups=groups, layers=layers,
                top_layers=sorted(layers, key=lambda item: item['cycles'], reverse=True)[:10],
                heads=["99860b0f", "98155281"], detections=detections,
                uart_sha256=hashlib.sha256(raw).hexdigest().upper(),
                scope="Per-layer target mcycle windows include operator CPU/MMIO/memory work. "
                      "Profile rows print after forward timing. Outside windows include loop, "
                      "sampling/store and progress UART work; this is not pure instrumentation cost. "
                      "Build layout and instrumentation can affect performance. "
                      "No hardware-event breakdown or multi-image accuracy claim.")
    if stack is not None:
        result['tcm_stack'] = stack
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("uart_log", type=Path)
    parser.add_argument("--graph", type=Path,
                        default=Path(__file__).resolve().parents[1] / "sw/yolo_fixed/model_graph.h")
    parser.add_argument("--nominal-hz", type=int, default=100_000_000)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    graph, graph_sha = read_graph(args.graph)
    result = summarize(args.uart_log.read_bytes(), graph, args.nominal_hz)
    result['model_graph_sha256'] = graph_sha
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in ['layers', 'top_layers', 'scope']}, indent=2))


if __name__ == "__main__":
    main()
