#!/usr/bin/env python3
"""Robust downloader for CH4-SpaceApps real-data manifest.

Features:
 - Resumes partial downloads with HTTP Range requests
 - Retries with exponential backoff on network/throttle errors
 - Optional MD5 checksum verification
 - Streams to disk in 64KB chunks (no memory blowup on large files)
 - Per-read timeout; prints progress every ~5s
"""
import hashlib
import json
import os
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data" / "real"

CHUNK = 65536
PER_READ_TIMEOUT = 60         # seconds without any bytes = abort this attempt
MAX_ATTEMPTS = 8
BASE_BACKOFF = 5              # seconds, doubled each retry (cap 120s)


def md5_of(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url, dest, expected_size=None, expected_md5=None):
    dest.parent.mkdir(parents=True, exist_ok=True)
    # Skip if already complete & verified
    if dest.exists():
        size = dest.stat().st_size
        if expected_size is not None and size == expected_size:
            if expected_md5 is None or md5_of(dest) == expected_md5:
                print(f"  SKIP (already complete): {dest.name}")
                return True
            print(f"  MD5 mismatch, redownloading {dest.name}")
            dest.unlink()
        elif expected_size is not None and size > expected_size:
            print(f"  size > expected, redownloading {dest.name}")
            dest.unlink()

    for attempt in range(1, MAX_ATTEMPTS + 1):
        start_byte = dest.stat().st_size if dest.exists() else 0
        headers = {
            "User-Agent": "ch4-spaceapps-downloader/1.0",
            "Accept": "*/*",
        }
        if start_byte > 0:
            headers["Range"] = f"bytes={start_byte}-"
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=PER_READ_TIMEOUT) as resp:
                status = resp.status
                if start_byte > 0 and status not in (206, 200):
                    print(f"  server ignored resume (status={status}); restarting")
                    dest.unlink(missing_ok=True)
                    start_byte = 0
                total = None
                cl = resp.headers.get("Content-Length")
                if cl is not None:
                    total = int(cl) + start_byte
                mode = "ab" if start_byte > 0 else "wb"
                t0 = time.time()
                last_report = t0
                with dest.open(mode) as out:
                    while True:
                        chunk = resp.read(CHUNK)
                        if not chunk:
                            break
                        out.write(chunk)
                        now = time.time()
                        if now - last_report >= 5:
                            cur = dest.stat().st_size
                            pct = (100.0 * cur / total) if total else 0.0
                            speed = (cur - start_byte) / max(1e-6, now - t0) / 1024
                            tag = f"{pct:5.1f}%" if total else "  ???"
                            print(f"  {tag}  {cur:>12,} B  {speed:7.1f} KB/s  {dest.name}")
                            last_report = now
            size = dest.stat().st_size
            if expected_size is not None and size != expected_size:
                print(f"  short read ({size}/{expected_size}), retrying")
                raise IOError("short read")
            if expected_md5 is not None:
                got = md5_of(dest)
                if got != expected_md5:
                    print(f"  MD5 mismatch ({got} vs {expected_md5}); restarting")
                    dest.unlink(missing_ok=True)
                    raise IOError("md5 mismatch")
            print(f"  OK: {dest.name} ({size:,} B)")
            return True
        except (urllib.error.URLError, urllib.error.HTTPError,
                TimeoutError, ConnectionError, IOError, OSError) as e:
            backoff = min(120, BASE_BACKOFF * (2 ** (attempt - 1)))
            print(f"  attempt {attempt}/{MAX_ATTEMPTS} failed: {e!r}; sleep {backoff}s")
            time.sleep(backoff)
    print(f"  FAILED: {dest.name}")
    return False


def run_manifest(manifest_path):
    with manifest_path.open("r", encoding="utf-8") as f:
        manifest = json.load(f)
    failed = 0
    total = len(manifest)
    for i, item in enumerate(manifest, 1):
        print(f"[{i}/{total}] {item['url']}")
        ok = download(
            url=item["url"],
            dest=ROOT / item["dest"],
            expected_size=item.get("size"),
            expected_md5=item.get("md5"),
        )
        if not ok:
            failed += 1
    print(f"\nDone. failed={failed}/{total}")
    return failed


if __name__ == "__main__":
    manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "tools" / "download_manifest.json"
    sys.exit(run_manifest(manifest))
