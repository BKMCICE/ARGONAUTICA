"""Pack a flat little-endian binary into 256-bit lines for DDR simulation."""
import argparse
from pathlib import Path


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input", type=Path)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()
    data = args.input.read_bytes()
    if len(data) > 65536:
        raise SystemExit("DDR simulation model supports at most 64 KiB")
    data += b"\0" * (-len(data) % 32)
    lines = [f"{int.from_bytes(data[i:i+32], 'little'):064x}" for i in range(0, len(data), 32)]
    args.output.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"{len(lines)} lines -> {args.output}")


if __name__ == "__main__":
    main()
