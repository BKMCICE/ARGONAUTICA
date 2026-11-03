"""bin2hex.py - convert a raw binary into a word-per-line hex file for $readmemh.

Usage: python bin2hex.py <input.bin> <output.hex> [--base-addr N]
Little-endian 32-bit words. If --base-addr is given (byte address of the
first byte of the binary), an "@<word_index>" marker is emitted first.
"""
import argparse
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("inp")
    ap.add_argument("out")
    ap.add_argument("--base-addr", type=lambda s: int(s, 0), default=0)
    ap.add_argument("--pad-words", type=int, default=0, help="pad with NOPs to this many words (avoids $readmemh short-file warning / vvp instability)")
    a = ap.parse_args()
    data = Path(a.inp).read_bytes()
    data += b"\0" * ((-len(data)) % 4)
    lines = []
    if a.base_addr:
        lines.append(f"@{a.base_addr // 4:08x}")
    for i in range(0, len(data), 4):
        lines.append(f"{int.from_bytes(data[i:i+4], 'little'):08x}")
    while a.pad_words and len(lines) < a.pad_words:
        lines.append("00000013")
    Path(a.out).write_text("\n".join(lines) + "\n", encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
