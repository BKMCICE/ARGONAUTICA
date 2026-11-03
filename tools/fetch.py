"""Download a GitHub release asset with resume and mirror fallback.

Usage: python fetch.py <github_url> <output_path>
- Uses Python's TLS stack (this machine's curl fails CRL checks on GitHub).
- Learns the total size from Content-Length and keeps resuming (HTTP Range)
  until the file is complete, rotating through mirrors on failure.
"""
import os
import sys
import time
import urllib.request

MIRRORS = [
    "",  # direct
    "https://ghfast.top/",
    "https://gh-proxy.com/",
    "https://ghproxy.net/",
    "https://mirror.ghproxy.com/",
]


def attempt(url: str, out: str, total: int | None):
    """One download attempt; returns (ok, total)."""
    have = os.path.getsize(out) if os.path.exists(out) else 0
    if total is not None and have >= total:
        return True, total
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
    if have:
        req.add_header("Range", f"bytes={have}-")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            if have and r.status != 206:
                have = 0  # server ignored Range: restart
            cl = r.headers.get("Content-Length")
            if r.status == 206:
                cr = r.headers.get("Content-Range", "")
                if "/" in cr:
                    total = int(cr.rsplit("/", 1)[1])
            elif cl:
                total = int(cl)
            print(f"[{url[:48]}] status={r.status} total={total} resume_from={have}", flush=True)
            t0 = time.time()
            last = t0
            done = have
            with open(out, "ab" if have else "wb") as f:
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
                    done += len(chunk)
                    if time.time() - last >= 10:
                        last = time.time()
                        print(f"  {done/1048576:.0f} MB", flush=True)
            ok = total is not None and done >= total
            print(f"  stopped at {done/1048576:.1f} MB after {time.time()-t0:.0f}s ({'complete' if ok else 'incomplete'})", flush=True)
            return ok, total
    except Exception as e:  # noqa: BLE001
        print(f"  error via {url[:48]}: {e}", flush=True)
        return False, total


def main() -> int:
    url, out = sys.argv[1], sys.argv[2]
    total = None
    for round_ in range(12):
        for prefix in MIRRORS:
            ok, total = attempt(prefix + url, out, total)
            if ok:
                print(f"DONE {out} ({total} bytes)", flush=True)
                return 0
            time.sleep(3)
    print("FAILED: exhausted retries", flush=True)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
