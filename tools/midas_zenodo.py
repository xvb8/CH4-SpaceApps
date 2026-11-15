#!/usr/bin/env python3
"""
MIDAS (ModIs Dust AeroSol) fetcher via Zenodo API.

Source: https://zenodo.org/records/4244106

MIDAS provides daily dust optical depth at 550 nm, 0.1 deg resolution, for
MODIS-Aqua C061 observations.  Each year is one tar.gz of ~4.3 GB; the full
record covers 2003-2017 plus a 2018 partial = ~65 GB total.

The Zenodo REST API gives file listings and direct download URLs.
No authentication is required for open-access records.

Usage:
  # List files and sizes
  python tools/midas_zenodo.py --list

  # Fetch a single year
  python tools/midas_zenodo.py --year 2005 --out data/real/midas/

  # Fetch a range
  python tools/midas_zenodo.py --start 2015 --end 2017 --out data/real/midas/

  # Fetch everything (~65 GB -- make sure you have the disk space)
  python tools/midas_zenodo.py --all --out data/real/midas/

  # Optional: auto-extract tar.gz after download
  python tools/midas_zenodo.py --year 2005 --out data/real/midas/ --extract
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import tarfile
import urllib.request
from pathlib import Path

RECORD = "4244106"
API = f"https://zenodo.org/api/records/{RECORD}"
UA = "CH4-SpaceApps/1.0 (MIDAS Zenodo fetcher)"
YEAR_RE = re.compile(r"-(\d{4})\.tar\.gz$")


def fetch_record() -> dict:
    req = urllib.request.Request(API, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode("utf-8"))


def files_by_year(rec: dict) -> dict[int, dict]:
    """Return {year: file_entry} for all per-year tar.gz files."""
    out: dict[int, dict] = {}
    for f in rec.get("files", []):
        m = YEAR_RE.search(f["key"])
        if m:
            out[int(m.group(1))] = f
    return out


def download(url: str, dest: Path, size_hint: int | None = None) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    resume_from = dest.stat().st_size if dest.exists() else 0
    if size_hint and resume_from >= size_hint:
        print(f"  already complete: {dest.name}  {resume_from/1e9:.2f} GB")
        return True

    req = urllib.request.Request(url, headers={"User-Agent": UA})
    if resume_from:
        req.add_header("Range", f"bytes={resume_from}-")
    mode = "ab" if resume_from else "wb"

    try:
        with urllib.request.urlopen(req, timeout=300) as r, open(dest, mode) as f:
            got = resume_from
            last_print = 0
            while True:
                chunk = r.read(1 << 20)  # 1 MB
                if not chunk:
                    break
                f.write(chunk)
                got += len(chunk)
                if got - last_print >= 100 * (1 << 20):  # 100 MB
                    if size_hint:
                        pct = 100.0 * got / size_hint
                        print(f"    {dest.name}: {got/1e9:.2f}/{size_hint/1e9:.2f} GB ({pct:.1f}%)")
                    else:
                        print(f"    {dest.name}: {got/1e9:.2f} GB")
                    last_print = got
            print(f"  ok: {dest.name}  {got/1e9:.2f} GB")
            return True
    except urllib.error.HTTPError as e:
        if e.code == 416 and resume_from:
            print(f"  already complete: {dest.name}  {resume_from/1e9:.2f} GB")
            return True
        print(f"  HTTP {e.code}: {e.reason}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"  error: {e}", file=sys.stderr)
        return False


def extract(tar_path: Path, out_dir: Path) -> bool:
    """Extract a tar.gz into out_dir (safe-only members)."""
    out_dir.mkdir(parents=True, exist_ok=True)
    try:
        with tarfile.open(tar_path, "r:gz") as t:
            # Guard against path traversal
            for m in t.getmembers():
                if m.name.startswith("/") or ".." in m.name.split("/"):
                    print(f"  SKIP unsafe entry {m.name}", file=sys.stderr)
                    continue
                t.extract(m, out_dir)
        print(f"  extracted -> {out_dir}")
        return True
    except Exception as e:
        print(f"  extract error: {e}", file=sys.stderr)
        return False


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--year", type=int, help="single year to fetch")
    ap.add_argument("--start", type=int, help="start year inclusive")
    ap.add_argument("--end", type=int, help="end year inclusive")
    ap.add_argument("--all", action="store_true", help="fetch every year (~65 GB)")
    ap.add_argument("--list", action="store_true", help="list files and exit")
    ap.add_argument("--extract", action="store_true",
                    help="unpack each tar.gz after download")
    ap.add_argument("--out", default="data/real/midas", help="output directory")
    args = ap.parse_args()

    print("Fetching Zenodo record metadata...")
    rec = fetch_record()
    byy = files_by_year(rec)

    if args.list:
        print(f"MIDAS Zenodo record {RECORD}:")
        print(f"Title: {rec.get('metadata', {}).get('title', '?')}")
        print(f"Years available ({len(byy)}):")
        for y in sorted(byy):
            f = byy[y]
            print(f"  {y}  {f['key']:70s}  {f['size']/1e9:.2f} GB")
        # Non-year files (README etc.)
        extras = [f for f in rec.get("files", []) if not YEAR_RE.search(f["key"])]
        if extras:
            print("Extras:")
            for f in extras:
                print(f"       {f['key']}  {f['size']/1e6:.2f} MB")
        return

    # Pick targets
    if args.year is not None:
        targets = [args.year]
    elif args.all:
        targets = sorted(byy.keys())
    elif args.start is not None and args.end is not None:
        if args.start > args.end:
            ap.error("--start must be <= --end")
        targets = [y for y in range(args.start, args.end + 1) if y in byy]
    else:
        ap.error("supply --year YYYY, --start/--end, --all, or --list")

    out = Path(args.out)
    ok = 0
    for y in targets:
        if y not in byy:
            print(f"[{y}] not in archive, skipping", file=sys.stderr)
            continue
        f = byy[y]
        url = f["links"]["self"]
        dest = out / f["key"]
        print(f"[{y}] {f['key']}  {f['size']/1e9:.2f} GB")
        if download(url, dest, size_hint=f["size"]):
            ok += 1
            if args.extract:
                extract(dest, out / str(y))

    print(f"\nDone: {ok}/{len(targets)} files in {out}")


if __name__ == "__main__":
    main()
