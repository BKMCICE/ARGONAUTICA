"""Verify an extracted handoff, capture UART, or relocate its ILA FIC."""
import argparse
import hashlib
import json
import time
from pathlib import Path


def verify(root: Path) -> int:
    root = root.resolve()
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    for name, expected in manifest["files"].items():
        path = (root / name).resolve()
        path.relative_to(root)
        data = path.read_bytes()
        if len(data) != expected["bytes"] or hashlib.sha256(data).hexdigest().upper() != expected["sha256"]:
            raise ValueError(f"File differs from manifest: {name}")
    print(f"HANDOFF_VERIFY_PASS files={len(manifest['files'])} commit={manifest['source_commit']}")
    return len(manifest["files"])


def prepare_debug(root: Path) -> Path:
    root = root.resolve()
    adf = root / "debug/pangu50k_ddr_top_syn.adf"
    if not adf.is_file():
        raise FileNotFoundError(adf)
    original = (root / "debug/pangu50k_ddr_top_ila.fic").read_text(encoding="utf-8")
    key = "Project.device.designInputFile="
    if sum(line.startswith(key) for line in original.splitlines()) != 1:
        raise ValueError("FIC must contain exactly one designInputFile")
    updated = "\n".join(key + adf.as_posix() if line.startswith(key) else line
                        for line in original.splitlines()) + "\n"
    output = root / "debug/pangu50k_ddr_top_ila_local.fic"
    output.write_text(updated, encoding="utf-8")
    print(f"Local FIC: {output}")
    return output


def capture(port: str, baud: int, output: Path, seconds: float) -> None:
    try:
        import serial
    except ImportError as exc:
        raise SystemExit("Install pyserial: python -m pip install pyserial") from exc
    output.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive create keeps the previous board measurements intact.
    with output.open("xb") as log, serial.Serial(port, baudrate=baud, timeout=0.2) as link:
        print(f"UART ready: {port} {baud} 8N1. Reset/program now. Log: {output}", flush=True)
        started = time.monotonic()
        try:
            while not seconds or time.monotonic() - started < seconds:
                data = link.read(256)
                if data:
                    log.write(data)
                    log.flush()
                    print(data.decode("ascii", errors="replace"), end="", flush=True)
        except KeyboardInterrupt:
            print("\nUART capture stopped.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("verify", "prepare-debug"):
        command = commands.add_parser(name)
        command.add_argument("--root", type=Path, default=Path.cwd())
    command = commands.add_parser("capture")
    command.add_argument("--port", required=True)
    command.add_argument("--baud", type=int, default=115200)
    command.add_argument("--log-file", type=Path, required=True)
    command.add_argument("--seconds", type=float, default=0)
    args = parser.parse_args()
    if args.command == "verify":
        verify(args.root)
    elif args.command == "prepare-debug":
        prepare_debug(args.root)
    else:
        if args.seconds < 0:
            parser.error("--seconds must be nonnegative")
        capture(args.port, args.baud, args.log_file, args.seconds)


if __name__ == "__main__":
    main()
