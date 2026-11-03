"""Create a checked board-test bundle, optionally with full committed sources."""
import argparse
import hashlib
import json
import io
import posixpath
import subprocess
import tarfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


EXPECTED = {
    "bitstreams/01_hello_s5.sbit": "CE1E2070CAC29E5EDE1FDF456953A5C91AC6A9BA6D481AEB23A40AD5C3780DE9",
    "bitstreams/02_coremark_2000.sbit": "C8CBA3CBD420A34714DD5B8F8CA52CA1BE14580F51761772C8F9FCAF5902F5D2",
    "bitstreams/03_ddr_hdmi_bootloader.sbit": "C76BAAE8D18FCAC488E47CDFC6F70413FD6F0F7D574D86CF810B4F2B6041D43B",
    "bitstreams/04_ddr_hdmi_ila.sbit": "5021FEE1F0335A3A6E996D4FBEE9FB4380DA7FADFFECF683D942A20F500B26EB",
    "debug/pangu50k_ddr_top_ila.fic": "B04C3C6C502BAE04E5841BD791182336681724DEED14BD838A3972FB3BA6A9D2",
    "firmware/hello_100mhz_115200.hex": "B5B378AC6AE00A56320842DDCFE113795779604814FA4BD89556ECEDF1FBECB0",
    "firmware/coremark_100mhz_115200_2000.hex": "1434447EF61DFE37E1412BC99E9D5744DFBA7F8D354DB991BCD0F6A0FCF8711A",
    "firmware/yolo_uart.bin": "BDD87CB56F9C138B259772C0523391E24EE03DE12B71545D776C3112F36E42C3",
    "frames/yolo_uart_boot.frame": "0708D4E2BA2114EE819B7791812B7763E725AC0F91E1DCEAB8B046C371FB95AE",
    "frames/dog.frame": "6068E35E2805A14167876611AB91B80CE3E34E760F34A421F4383196D8AE1835",
    "firmware/coremark_ddr_100mhz_115200_2000.bin": "44DDCE4EEA3F15A34EC21B18A046AF9A2171A64446A6DF45489FA2D9E3829014",
    "debug/pangu50k_ddr_top_syn.adf": "035BEF05976B460531A3B822487C0F19A9E3B8A270D27B0A8E48BCE2E8B9A091",
    "reports/ddr_hdmi_base.rtr": "2C7415632BD859CC545B843B607E1B80BC48A41E59975D562CF808BE4A33D736",
    "reports/ddr_hdmi_ila.rtr": "FCE6D80481B4C929F8F2CD2C6FB03BA9F142AF6FD351B1968CE80507AFC58D6C",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def add_bytes(bundle: ZipFile, name: str, data: bytes, mode: int = 0o644) -> None:
    info = ZipInfo(name, date_time=(2026, 10, 14, 0, 0, 0))
    info.compress_type = ZIP_DEFLATED
    info.external_attr = (0o100000 | mode) << 16
    bundle.writestr(info, data)


def source_snapshot(repo: Path, commit: str) -> tuple[dict, dict]:
    """Archive committed blobs and recursively pinned submodules, without .git."""
    files, metadata, links = {}, {}, {}

    def collect(directory: Path, revision: str, prefix: str) -> None:
        archive = subprocess.check_output(["git", "archive", "--format=tar", revision], cwd=directory)
        with tarfile.open(fileobj=io.BytesIO(archive)) as contents:
            for member in contents:
                name = prefix + member.name
                if member.isfile():
                    files[name] = contents.extractfile(member).read()
                    metadata[name] = {"source": f"git:{revision}:{member.name}", "mode": member.mode}
                elif member.issym():
                    links[name] = posixpath.normpath(posixpath.join(posixpath.dirname(name), member.linkname))
        tree = subprocess.check_output(["git", "ls-tree", "-rz", revision], cwd=directory)
        for record in tree.split(b"\0"):
            if not record:
                continue
            info, path = record.split(b"\t", 1)
            mode, kind, sha = info.decode().split()
            if mode == "160000":
                relative = path.decode("utf-8")
                collect(directory / relative, sha, prefix + relative + "/")

    collect(repo, commit, "source/")
    while links:
        resolved = [name for name, target in links.items() if target in files]
        if not resolved:
            raise ValueError(f"Unresolvable source symlinks: {links}")
        for name in resolved:
            target = links.pop(name)
            files[name] = files[target]
            metadata[name] = {"source": f"materialized symlink to {target}", "mode": metadata[target]["mode"]}
    return files, metadata


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--work-root", type=Path, required=True)
    ap.add_argument("--output-dir", type=Path, required=True)
    ap.add_argument("--include-source", action="store_true",
                    help="include all committed files and recursively pinned submodule contents")
    args = ap.parse_args()
    repo = Path(__file__).resolve().parent.parent
    work = args.work_root.resolve()
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo,
                                     text=True).strip()
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=repo).strip():
        raise RuntimeError("commit or discard workspace changes before packaging")
    paths = {
        "bitstreams/01_hello_s5.sbit": work / "pds/pds_build_s5_20260923/generate_bitstream/pangu50k_top.sbit",
        "bitstreams/02_coremark_2000.sbit": work / "pds/pds_build_coremark_20260923/generate_bitstream/pangu50k_top.sbit",
        "bitstreams/03_ddr_hdmi_bootloader.sbit": work / "pds/pds_build_ddr_reset_s22_base_20261014/generate_bitstream/pangu50k_ddr_top.sbit",
        "bitstreams/04_ddr_hdmi_ila.sbit": work / "pds/pds_build_ddr_reset_s22_strict_20261014/generate_bitstream/pangu50k_ddr_top.sbit",
        "debug/pangu50k_ddr_top_ila.fic": work / "pds/pds_build_ddr_reset_s22_strict_20261014/pangu50k_ddr_top_ila.fic",
        "firmware/hello_100mhz_115200.hex": repo / "firmware/hello_100mhz_115200.hex",
        "firmware/coremark_100mhz_115200_2000.hex": repo / "firmware/coremark_100mhz_115200_2000.hex",
        "firmware/yolo_uart.bin": repo / "sw/yolo_fixed/build_uart/yolo_fixed.bin",
        "frames/yolo_uart_boot.frame": work / "firmware/yolo_uart_boot_timed.frame",
        "frames/dog.frame": work / "firmware/dog.frame",
        "models/dog.jpg": repo / "models/yolo_fastest_1_1/dog.jpg",
        "tools/uart_boot.py": repo / "tools/uart_boot.py",
        "tools/yolo_prepare_image.py": repo / "tools/yolo_prepare_image.py",
        "tools/board_test_helper.py": repo / "tools/board_test_helper.py",
        "firmware/coremark_ddr_100mhz_115200_2000.bin": repo / "firmware/coremark_ddr_100mhz_115200_2000.bin",
        "debug/pangu50k_ddr_top_syn.adf": work / "pds/pds_build_ddr_reset_s22_strict_20261014/synthesize/pangu50k_ddr_top_syn.adf",
        "reports/ddr_hdmi_base.rtr": work / "pds/pds_build_ddr_reset_s22_base_20261014/report_timing/pangu50k_ddr_top.rtr",
        "reports/ddr_hdmi_ila.rtr": work / "pds/pds_build_ddr_reset_s22_strict_20261014/report_timing/pangu50k_ddr_top.rtr",
        "reports/yolo_rtl_result.log": repo / "docs/validation/20260925-s19-rtl-yolo-complete/result_excerpt.log",
        "BOARD_TEST_GUIDE.md": repo / "docs/board_test_guide.md",
        "BOARD_TEST_RESULTS_TEMPLATE.md": repo / "docs/board_test_results_template.md",
    }
    entries = {}
    payloads = {}
    for name, path in paths.items():
        data = path.read_bytes()
        digest = sha256(data)
        if name in EXPECTED and digest != EXPECTED[name]:
            raise ValueError(f"hash mismatch for {name}: {digest}")
        entries[name] = {"bytes": len(data), "sha256": digest,
                         "source": str(path)}
        payloads[name] = data
    if args.include_source:
        source_files, source_info = source_snapshot(repo, commit)
        for name, data in source_files.items():
            payloads[name] = data
            entries[name] = {"bytes": len(data), "sha256": sha256(data), **source_info[name]}
    readme = (
        "ARGONAUTICA MES50HP board handoff -- S22 DDR RESET REPAIR\n"
        f"Source commit: {commit}\n\n"
        "Start with BOARD_TEST_GUIDE.md (Chinese), then verify manifest.json:\n"
        "  python tools/board_test_helper.py verify\n"
        "Four verified candidate bitstreams are in bitstreams/.\n"
        "Start UART capture BEFORE programming/reset. KEY1 resets only the RAM"
        " images (01/02); reprogram the DDR image (03/04) for each run.\n"
        "For YOLO, start this command and then program image 03 within 60 s:\n"
        "  python -u tools/uart_boot.py firmware/yolo_uart.bin --port COMx"
        " --ai-image-frame frames/dog.frame\n"
        "Expect heads 99860b0f/98155281, six detections and HDMI green 82.\n"
        "Optional ILA setup: python tools/board_test_helper.py prepare-debug\n"
        "The original FIC and matching synthesis ADF are in debug/.\n"
        "Full committed sources/submodules are in source/ when --include-source"
        " was used. Toolchains and PDS licenses are not bundled.\n"
        "Board evidence and validation boundaries are recorded in source/docs/validation/"
        "20261014-s22-ddr-reset/README.md. HDMI and camera acceptance is pending.\n"
    ).encode("utf-8")
    entries["README.txt"] = {"bytes": len(readme), "sha256": sha256(readme),
                             "source": "generated by tools/package_board_handoff.py"}
    manifest = {"project": "ARGONAUTICA", "source_commit": commit,
                "board": "MES50HP/PGL50H", "status": "partially board-validated; see S21/S22 records",
                "includes_source": args.include_source,
                "bitstream_provenance": {
                    "01_hello_s5.sbit": "S5 2026-09-23 RAM baseline; docs/validation/20260923-recovery/README.md",
                    "02_coremark_2000.sbit": "S5 2026-09-23 RAM baseline; docs/validation/20260923-recovery/README.md",
                    "03_ddr_hdmi_bootloader.sbit": "S22 DDR reset repair, base 7/23; docs/validation/20261014-s22-ddr-reset/README.md",
                    "04_ddr_hdmi_ila.sbit": "S22 DDR reset repair, DDR handshake probes 13/23; docs/validation/20261014-s22-ddr-reset/README.md",
                },
                "files": entries}
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    stem = f"ARGONAUTICA_board_handoff_{commit[:7]}"
    zip_path = output / f"{stem}.zip"
    manifest_path = output / f"{stem}.manifest.json"
    if zip_path.exists() or manifest_path.exists():
        raise FileExistsError("handoff files already exist; choose a new output directory")
    with ZipFile(zip_path, "w") as bundle:
        for name, data in payloads.items():
            add_bytes(bundle, name, data, entries[name].get("mode", 0o644))
        add_bytes(bundle, "README.txt", readme)
        add_bytes(bundle, "manifest.json", manifest_bytes)
    with ZipFile(zip_path) as bundle:
        if bundle.testzip() is not None:
            raise ValueError("ZIP CRC verification failed")
        for name, details in entries.items():
            if sha256(bundle.read(name)) != details["sha256"]:
                raise ValueError(f"ZIP payload hash mismatch for {name}")
        if bundle.read("manifest.json") != manifest_bytes:
            raise ValueError("ZIP manifest differs from generated manifest")
    manifest_path.write_bytes(manifest_bytes)
    print(f"bundle={zip_path} bytes={zip_path.stat().st_size} sha256={sha256(zip_path.read_bytes())}")
    print(f"manifest={manifest_path} entries={len(entries)} commit={commit}")


if __name__ == "__main__":
    main()
