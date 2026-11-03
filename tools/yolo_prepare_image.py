"""Prepare a 320x320 RGB image for the YOLO_UART_IMAGE firmware.

The output frame is a little-endian FNV-1a checksum followed by 307200
CHW signed INT8 bytes, using the same preprocessing as the host reference.
"""
import argparse
import hashlib
import struct
from pathlib import Path

import numpy as np
from PIL import Image


def prepare(path: Path) -> tuple[bytes, int]:
    with Image.open(path) as image:
        rgb = image.convert("RGB").resize((320, 320))
        chw = np.asarray(rgb, dtype=np.float32).transpose(2, 0, 1)
    data = np.rint(chw / 255.0 * 127.0).clip(-127, 127).astype(np.int8).tobytes()
    checksum = 2166136261
    for byte in data:
        checksum = ((checksum ^ byte) * 16777619) & 0xFFFFFFFF
    return data, checksum


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--frame-out", type=Path, required=True)
    args = parser.parse_args()
    data, checksum = prepare(args.image)
    args.frame_out.write_bytes(struct.pack("<I", checksum) + data)
    print(f"image_bytes={len(data)} fnv1a={checksum:08x} "
          f"sha256={hashlib.sha256(data).hexdigest()} "
          f"frame={args.frame_out}")


if __name__ == "__main__":
    main()
