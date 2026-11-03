"""Build/send an RV32 DDR boot frame (requires pyserial only with --port).

Examples:
  python tools/uart_boot.py sw/coremark/build/coremark.bin --frame-out coremark.frame
  python tools/uart_boot.py sw/coremark/build/coremark.bin --port COM5
"""
import argparse
import hashlib
import struct
import sys
import time
from pathlib import Path


def make_frame(payload: bytes) -> tuple[bytes, int]:
    if not 0 < len(payload) <= 0x00FFC000:
        raise ValueError("DDR image must be between 1 and 16760832 bytes")
    checksum = 2166136261
    for byte in payload:
        checksum = ((checksum ^ byte) * 16777619) & 0xFFFFFFFF
    return b"RV32" + struct.pack("<II", len(payload), checksum) + payload, checksum


def has_uart_line(data: bytes | bytearray, expected: bytes) -> bool:
    """Match a complete firmware line with either LF or UART CRLF endings."""
    return expected in bytes(data).replace(b"\r\n", b"\n").split(b"\n")[:-1]


def send_frame(port: str, baud: int, frame: bytes,
               ai_image_frame: bytes | None = None) -> None:
    try:
        import serial  # type: ignore[import-not-found]
    except ImportError as exc:
        raise SystemExit("Install pyserial to use --port: python -m pip install pyserial") from exc

    with serial.Serial(port, baudrate=baud, timeout=0.2, write_timeout=10) as link:
        print(f"Waiting for RV32BOOT1 on {port} (reset the board if needed)...", flush=True)
        banner = bytearray()
        deadline = time.monotonic() + 60
        while b"RV32BOOT1" not in banner:
            if time.monotonic() > deadline:
                raise TimeoutError("bootloader banner not received within 60 seconds")
            banner.extend(link.read(1))
            if len(banner) > 128:
                del banner[:-128]
        print("Bootloader ready; sending image...", flush=True)
        for offset in range(0, len(frame), 256):
            link.write(frame[offset:offset + 256])
        link.flush()
        result = bytearray()
        deadline = time.monotonic() + 30
        while not has_uart_line(result, b"GO") and b"BAD " not in result:
            if time.monotonic() > deadline:
                raise TimeoutError("bootloader did not acknowledge image")
            result.extend(link.read(1))
            if len(result) > 128:
                del result[:-128]
        if b"BAD " in result:
            raise RuntimeError(result.decode("ascii", errors="replace").strip())
        print("Image started. Serial output follows (Ctrl+C to stop):", flush=True)
        try:
            if ai_image_frame is not None:
                prompt = bytearray()
                deadline = time.monotonic() + 60
                while not has_uart_line(prompt, b"YOLO_INPUT 307200"):
                    if time.monotonic() > deadline:
                        raise TimeoutError("YOLO image prompt not received")
                    chunk = link.read(1)
                    if chunk:
                        sys.stdout.buffer.write(chunk)
                        sys.stdout.buffer.flush()
                        prompt.extend(chunk)
                        if len(prompt) > 128:
                            del prompt[:-128]
                for offset in range(0, len(ai_image_frame), 256):
                    link.write(ai_image_frame[offset:offset + 256])
                link.flush()
            while True:
                chunk = link.read(256)
                if chunk:
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.buffer.flush()
        except KeyboardInterrupt:
            print("\nSerial capture stopped.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="flat DDR binary linked at 0x80000000")
    parser.add_argument("--port", help="serial port, e.g. COM5; omit for offline frame generation")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--frame-out", type=Path, help="save the exact upload frame")
    parser.add_argument("--ai-image-frame", type=Path,
                        help="checksum + CHW INT8 image for a YOLO_UART_IMAGE firmware")
    args = parser.parse_args()
    payload = args.image.read_bytes()
    frame, checksum = make_frame(payload)
    print(f"bytes={len(payload)} fnv1a={checksum:08x} sha256={hashlib.sha256(payload).hexdigest()}")
    if args.frame_out:
        args.frame_out.write_bytes(frame)
        print(f"frame={args.frame_out} bytes={len(frame)}")
    if args.port:
        ai_frame = args.ai_image_frame.read_bytes() if args.ai_image_frame else None
        if ai_frame is not None:
            if len(ai_frame) != 307204:
                raise ValueError("AI image frame must be 307204 bytes")
            checksum = 2166136261
            for byte in ai_frame[4:]:
                checksum = ((checksum ^ byte) * 16777619) & 0xFFFFFFFF
            if checksum != struct.unpack("<I", ai_frame[:4])[0]:
                raise ValueError("AI image frame checksum mismatch")
        send_frame(args.port, args.baud, frame, ai_frame)


if __name__ == "__main__":
    main()
