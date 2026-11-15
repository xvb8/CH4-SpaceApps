#!/usr/bin/env python3
"""earthdata_cmr.py -- query NASA CMR and download granules via the public API.

No `earthaccess` dependency. Two steps:

1. SEARCH (unauthenticated):
     GET https://cmr.earthdata.nasa.gov/search/granules.json
     ?short_name=<SHORT>&version=<V>&bounding_box=<W,S,E,N>
     &temporal=<ISO,ISO>&page_size=<N>

2. DOWNLOAD (bearer-token authenticated):
     For each granule, follow every link whose `rel` ends with `/data#`.
     LP DAAC / GESDISC redirect through urs.earthdata.nasa.gov, so we
     attach `Authorization: Bearer <token>` on every request and follow
     redirects. The token is an Earthdata Login (EDL) User Access Token
     generated at https://urs.earthdata.nasa.gov/users/<name>/user_tokens
     (or https://urs.earthdata.nasa.gov/api/users/tokens).

Usage:
    set EARTHDATA_TOKEN=eyJ0eXAi...
    python tools\\earthdata_cmr.py EMITL2BMIN 002 ^
        --bbox -117.3 36.8 -117.0 37.1 ^
        --start 2023-01-01 --end 2024-12-31 ^
        --out data/real/earth_emit_l2b --max 2

Dry-run (no token needed, just prints URLs):
    python tools\\earthdata_cmr.py EMITL2BMIN 002 --bbox ... --list-only
"""
from __future__ import annotations
import argparse, json, os, sys, urllib.parse, urllib.request
from pathlib import Path

CMR = "https://cmr.earthdata.nasa.gov/search/granules.json"
DATA_REL_SUFFIX = "/data#"  # ESIP fedsearch: .../fedsearch/1.1/data#


def cmr_search(short_name, version, bbox, temporal, page_size=50, page_num=1):
    params = {
        "short_name": short_name,
        "version": version,
        "page_size": str(page_size),
        "page_num": str(page_num),
    }
    if bbox:
        params["bounding_box"] = ",".join(str(x) for x in bbox)
    if temporal:
        params["temporal"] = ",".join(temporal)
    url = CMR + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def data_urls(entry):
    # Collection-level "inherited" links (e.g. a search UI URL) also carry
    # rel=".../data#"; skip them and skip anything that doesn't look like
    # a direct file download.
    for link in entry.get("links", []):
        if link.get("inherited"):
            continue
        rel = link.get("rel", "")
        href = link.get("href", "")
        if not rel.endswith(DATA_REL_SUFFIX):
            continue
        if not href.startswith("https://"):
            continue
        # Direct file URLs end with a filename containing a '.' after the
        # last '/'. Search-UI URLs like ".../granules?p=C..." do not.
        tail = href.rsplit("/", 1)[-1]
        if "?" in tail or "." not in tail:
            continue
        yield href


def stream_download(url, dest, token, chunk=1 << 16):
    headers = {"Authorization": f"Bearer {token}"}
    resume_from = dest.stat().st_size if dest.exists() else 0
    if resume_from:
        headers["Range"] = f"bytes={resume_from}-"
    req = urllib.request.Request(url, headers=headers)
    mode = "ab" if resume_from else "wb"
    with urllib.request.urlopen(req, timeout=120) as r, open(dest, mode) as f:
        total = r.headers.get("Content-Length")
        total_i = int(total) + resume_from if total else None
        read = resume_from
        while True:
            buf = r.read(chunk)
            if not buf:
                break
            f.write(buf)
            read += len(buf)
            if total_i:
                pct = 100 * read / total_i
                print(f"\r  {dest.name}: {read/1e6:.1f} / {total_i/1e6:.1f} MB ({pct:.1f}%)", end="", flush=True)
        print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("short_name")
    ap.add_argument("version")
    ap.add_argument("--bbox", nargs=4, type=float, metavar=("W", "S", "E", "N"))
    ap.add_argument("--start")
    ap.add_argument("--end")
    ap.add_argument("--out", default="data/real/earthdata_cmr")
    ap.add_argument("--max", type=int, default=0, help="0 = all matching granules")
    ap.add_argument("--list-only", action="store_true")
    ap.add_argument("--page-size", type=int, default=50)
    args = ap.parse_args()

    temporal = None
    if args.start or args.end:
        temporal = (
            (args.start + "T00:00:00Z") if args.start else "",
            (args.end + "T23:59:59Z") if args.end else "",
        )

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    token = os.environ.get("EARTHDATA_TOKEN", "").strip()
    if not args.list_only and not token:
        print(
            "ERROR: set EARTHDATA_TOKEN env var (get one at "
            "https://urs.earthdata.nasa.gov/users/<name>/user_tokens)",
            file=sys.stderr,
        )
        sys.exit(2)

    collected = []
    page = 1
    while True:
        feed = cmr_search(
            args.short_name, args.version, args.bbox, temporal, args.page_size, page
        )["feed"]
        entries = feed.get("entry", [])
        if not entries:
            break
        for e in entries:
            for href in data_urls(e):
                collected.append((e.get("producer_granule_id", e.get("title", "?")), href))
                if args.max and len(collected) >= args.max:
                    break
            if args.max and len(collected) >= args.max:
                break
        if args.max and len(collected) >= args.max:
            break
        if len(entries) < args.page_size:
            break
        page += 1

    print(f"Found {len(collected)} data URL(s) across granules")
    for gid, href in collected:
        print(f"  {gid}  ->  {href.rsplit('/', 1)[-1]}")

    if args.list_only:
        return

    for gid, href in collected:
        name = href.rsplit("/", 1)[-1]
        dest = out / name
        print(f"\n> {name}")
        try:
            stream_download(href, dest, token)
        except Exception as ex:
            print(f"  FAILED: {ex}", file=sys.stderr)
    print(f"\nDone. {len(list(out.iterdir()))} file(s) in {out}")


if __name__ == "__main__":
    main()
