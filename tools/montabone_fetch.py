#!/usr/bin/env python3
"""
Montabone Mars Dust Climatology fetcher.

Downloads daily/sub-daily gridded or kriged Column Dust Optical Depth (CDOD)
NetCDF files from the Laboratoire de Meteorologie Dynamique (LMD) host:

    http://www-mars.lmd.jussieu.fr/mars/dust_climatology/dataset_v2/

Two product families, one file per Martian Year (MY 24 - MY 36):
    - griddedcdod_MY{N}_v{X}.nc    daily irregularly gridded CDOD
    - dustscenario_MY{N}_v{X}.nc   daily regularly kriged CDOD (GCM-ready)

Version tag per MY:
    MY 24-32  -> v2-0
    MY 33     -> v2-1
    MY 34-36  -> v2-5   (plus v2-5-1 gridded, four maps per sol)

Reference: Montabone et al., Icarus 2015 / 2020.
License: CC-BY-SA 3.0 (please tell the authors you downloaded it; see upstream
page for the Google Form link).

Usage examples:
    python montabone_fetch.py --list
    python montabone_fetch.py --product gridded  --year 34 --out data/real/montabone
    python montabone_fetch.py --product scenario --year 34 35 36 --out data/real/montabone
    python montabone_fetch.py --product gridded_subdiel --year 34
"""

from __future__ import annotations

import argparse
import sys
import urllib.request
import urllib.error
from pathlib import Path

BASE = "http://www-mars.lmd.jussieu.fr/mars/dust_climatology/dataset_v2/"

# (product-key, year) -> version tag that is used in the filename
VERSION_BY_YEAR = {
    24: "v2-0", 25: "v2-0", 26: "v2-0", 27: "v2-0", 28: "v2-0", 29: "v2-0",
    30: "v2-0", 31: "v2-0", 32: "v2-0",
    33: "v2-1",
    34: "v2-5", 35: "v2-5", 36: "v2-5",
}

SUBDIEL_YEARS = {34, 35, 36}  # v2-5-1 gridded, four maps per sol

PRODUCTS = {
    "gridded":          "griddedcdod",   # daily, irregularly gridded
    "scenario":         "dustscenario",  # daily, kriged (GCM-ready)
    "gridded_subdiel":  "griddedcdod",   # four maps per sol (MY34+ only)
}

YEARS_ALL = sorted(VERSION_BY_YEAR.keys())


def filename_for(product: str, year: int) -> str:
    if product not in PRODUCTS:
        raise ValueError(f"unknown product {product!r}")
    base = PRODUCTS[product]
    if product == "gridded_subdiel":
        if year not in SUBDIEL_YEARS:
            raise ValueError(f"subdiel product only exists for MY {sorted(SUBDIEL_YEARS)}")
        return f"{base}_MY{year}_v2-5-1.nc"
    ver = VERSION_BY_YEAR[year]
    return f"{base}_MY{year}_{ver}.nc"


def head_size(url: str) -> int | None:
    try:
        req = urllib.request.Request(url, method="HEAD",
                                     headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as r:
            cl = r.headers.get("Content-Length")
            return int(cl) if cl else None
    except Exception:
        return None


def download(url: str, dest: Path, chunk: int = 1 << 16) -> bool:
    """Resume-capable streaming download."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    resume_from = dest.stat().st_size if dest.exists() else 0
    total = head_size(url)
    if total is not None and resume_from >= total:
        print(f"  already complete ({resume_from} bytes): {dest.name}")
        return True

    headers = {"User-Agent": "Mozilla/5.0"}
    mode = "wb"
    if resume_from:
        headers["Range"] = f"bytes={resume_from}-"
        mode = "ab"
        print(f"  resume from {resume_from} bytes ({dest.name})")

    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=180) as r, open(dest, mode) as f:
            got = resume_from
            last_report = got
            while True:
                buf = r.read(chunk)
                if not buf:
                    break
                f.write(buf)
                got += len(buf)
                if got - last_report > (4 << 20):  # every ~4 MB
                    if total:
                        pct = 100.0 * got / total
                        print(f"    {got/1e6:7.2f} MB / {total/1e6:7.2f} MB ({pct:5.1f}%)")
                    else:
                        print(f"    {got/1e6:7.2f} MB")
                    last_report = got
        print(f"  ok: {dest}  ({got} bytes)")
        return True
    except urllib.error.HTTPError as e:
        print(f"  HTTP {e.code}: {url}")
    except Exception as e:
        print(f"  ERROR: {e}")
    return False


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--product", choices=sorted(PRODUCTS.keys()),
                   default="scenario",
                   help="gridded = daily gridded CDOD; "
                        "scenario = daily kriged CDOD (GCM-ready, default); "
                        "gridded_subdiel = 4 maps per sol (MY 34-36 only)")
    p.add_argument("--year", type=int, nargs="+", default=None,
                   help=f"Martian Year(s), one or more of {YEARS_ALL}. Default: all")
    p.add_argument("--out", default="data/real/montabone",
                   help="output directory (default: data/real/montabone)")
    p.add_argument("--list", action="store_true",
                   help="list URLs and sizes without downloading")
    args = p.parse_args()

    years = args.year or YEARS_ALL
    out_dir = Path(args.out)

    bad = []
    for y in years:
        try:
            fname = filename_for(args.product, y)
        except ValueError as e:
            print(f"[skip MY{y}] {e}")
            bad.append(y)
            continue
        url = BASE + fname
        if args.list:
            size = head_size(url)
            size_str = f"{size/1e6:7.2f} MB" if size else "    ?   "
            print(f"  {size_str}  {url}")
        else:
            dest = out_dir / fname
            print(f"[MY{y}] {url}")
            ok = download(url, dest)
            if not ok:
                bad.append(y)

    if bad:
        print(f"\nFailures: MY{bad}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
