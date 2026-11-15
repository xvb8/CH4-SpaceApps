#!/usr/bin/env python3
"""
PDS ODE REST API fetcher for Mars orbital datasets.

A single unified client that queries the PDS Orbital Data Explorer REST API
(https://oderest.rsl.wustl.edu/) for products and downloads the actual data
files.  Supported datasets:

  - HiRISE RDR v1.1     (ihid=MRO,  iid=HIRISE, pt=RDRV11)
  - CTX EDR             (ihid=MRO,  iid=CTX,    pt=EDR)
  - CRISM MTRDR         (ihid=MRO,  iid=CRISM,  pt=MTRDR)
  - MCS DDR             (ihid=MRO,  iid=MCS,    pt=DDR)

The ODE API resolves spatial / date / product-id queries and returns direct
URLs to the archival data files hosted at HiRISE-PDS, PDS-Geosciences,
atmos.nmsu.edu, and planetarydata.jpl.nasa.gov.

Usage:
  # List 5 HiRISE RDRs near Jezero crater
  python tools/pds_ode_fetch.py --dataset hirise --bbox 17 19 76 78 --limit 5 --list

  # Download the actual JP2 (and label) for those products
  python tools/pds_ode_fetch.py --dataset hirise --bbox 17 19 76 78 --limit 5 \
      --out data/real/hirise/ --types Product

  # One CTX EDR by product id
  python tools/pds_ode_fetch.py --dataset ctx --pdsid MOI_000009_0186_XI_18S051W \
      --out data/real/ctx/

  # One MCS DDR day
  python tools/pds_ode_fetch.py --dataset mcs --bbox -90 90 -180 180 \
      --start 2008-01-01 --end 2008-01-02 --limit 10 --out data/real/mcs/

  # Just list with full URLs (no download)
  python tools/pds_ode_fetch.py --dataset crism --bbox 18 19 77 78 --limit 2 --list --verbose
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://oderest.rsl.wustl.edu/live2/"
UA = "CH4-SpaceApps/1.0 (PDS ODE fetcher)"

# dataset-slug -> (ihid, iid, pt) triple for the ODE query
DATASETS = {
    "hirise": ("MRO", "HIRISE", "RDRV11"),
    "ctx":    ("MRO", "CTX",    "EDR"),
    "crism":  ("MRO", "CRISM",  "MTRDR"),
    "mcs":    ("MRO", "MCS",    "DDR"),
}


def ode_query(params: dict) -> dict:
    """Call the ODE REST API and return parsed JSON."""
    base = {
        "target": "mars",
        "query": "product",
        "results": "fp",   # include file list
        "output": "JSON",
    }
    base.update(params)
    url = API + "?" + urllib.parse.urlencode(base)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode("utf-8"))


def iter_products(payload: dict):
    """Yield product dicts from an ODE response, tolerating both single and list shapes."""
    results = payload.get("ODEResults", {})
    if results.get("Status") == "ERROR":
        msg = results.get("Error", "Unknown ODE error")
        raise RuntimeError(f"ODE error: {msg}")
    products = results.get("Products", {}).get("Product")
    if products is None:
        return
    if isinstance(products, list):
        for p in products:
            yield p
    else:
        yield products


def iter_files(product: dict):
    """Yield file dicts from a product, tolerating single vs list."""
    files = product.get("Product_files", {}).get("Product_file")
    if files is None:
        return
    if isinstance(files, list):
        for f in files:
            yield f
    else:
        yield files


def download(url: str, dest: Path, chunk: int = 1 << 16) -> None:
    """Resume-capable download with HTTP Range."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    resume_from = dest.stat().st_size if dest.exists() else 0
    headers = {"User-Agent": UA}
    if resume_from > 0:
        headers["Range"] = f"bytes={resume_from}-"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            mode = "ab" if resume_from > 0 and r.status == 206 else "wb"
            total = resume_from if mode == "ab" else 0
            with open(dest, mode) as f:
                while True:
                    buf = r.read(chunk)
                    if not buf:
                        break
                    f.write(buf)
                    total += len(buf)
            print(f"  -> {dest.name} ({total/1e6:.2f} MB)")
    except urllib.error.HTTPError as e:
        if e.code == 416:
            print(f"  -> {dest.name} already complete")
            return
        raise


def build_params(args) -> dict:
    ihid, iid, pt = DATASETS[args.dataset]
    params = {"ihid": ihid, "iid": iid, "pt": pt, "limit": args.limit}
    if args.pdsid:
        params["pdsid"] = args.pdsid
    if args.bbox:
        minlat, maxlat, wlon, elon = args.bbox
        params["minlat"] = minlat
        params["maxlat"] = maxlat
        params["westernlon"] = wlon
        params["easternlon"] = elon
    if args.start:
        params["observationtimestart"] = args.start
    if args.end:
        params["observationtimeend"] = args.end
    return params


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dataset", choices=sorted(DATASETS), required=True,
                   help="Which PDS ODE dataset to query")
    p.add_argument("--bbox", type=float, nargs=4, metavar=("MINLAT", "MAXLAT", "WLON", "ELON"),
                   help="Bounding box in degrees (lon 0..360 east)")
    p.add_argument("--pdsid", help="Exact PDS product id to fetch")
    p.add_argument("--start", help="Observation start time (ISO, e.g. 2008-01-01)")
    p.add_argument("--end",   help="Observation end time (ISO)")
    p.add_argument("--limit", type=int, default=10, help="Max products to return (default 10)")
    p.add_argument("--types", nargs="+", default=["Product"],
                   help="Which Product_file Type values to download (e.g. Product Browse Derived). Default: Product.")
    p.add_argument("--out", type=Path, help="Output directory (required unless --list)")
    p.add_argument("--list", action="store_true", help="List matching products only, do not download")
    p.add_argument("--verbose", action="store_true", help="Print each file URL as it is seen")
    args = p.parse_args()

    if not args.list and args.out is None:
        p.error("--out is required unless --list is used")
    if not (args.bbox or args.pdsid or args.start or args.end):
        p.error("Provide at least one of --bbox / --pdsid / --start / --end")

    params = build_params(args)
    print(f"ODE query: {params}")
    payload = ode_query(params)

    products = list(iter_products(payload))
    print(f"\n{len(products)} product(s) returned")

    if not products:
        return 0

    type_filter = set(t.lower() for t in args.types)
    total_bytes = 0
    for prod in products:
        pdsid = prod.get("pdsid", "?")
        volume = prod.get("PDSVolume_Id", "?")
        print(f"\n[{pdsid}]  volume={volume}")
        for fdict in iter_files(prod):
            ftype = fdict.get("Type", "")
            url = fdict.get("URL", "")
            name = fdict.get("FileName", "")
            kb = fdict.get("KBytes", "?")
            if args.verbose or args.list:
                print(f"  {ftype:9s} {kb:>8s} KB  {name}")
                if args.verbose:
                    print(f"             URL: {url}")
            if args.list:
                continue
            if ftype.lower() not in type_filter:
                continue
            dest = args.out / pdsid / name
            try:
                download(url, dest)
                try:
                    total_bytes += int(kb) * 1024
                except (TypeError, ValueError):
                    pass
            except Exception as e:
                print(f"  !! failed {name}: {e}")

    if not args.list:
        print(f"\nTotal downloaded (nominal): {total_bytes/1e6:.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
