#!/usr/bin/env python3
"""
ESA CCI Permafrost L4 v05.0 northern-hemisphere pp fetcher (CEDA archive).

Source: https://data.ceda.ac.uk/neodc/esacci/permafrost/data/permafrost_extent/L4/area4/pp/v05.0/northern_hemisphere/

The CEDA archive lists one subdirectory per year (1997, 1998, ..., 2019+),
each containing a single NetCDF file:

    ESACCI-PERMAFROST-L4-PFR-MODISLST_CRYOGRID-AREA4_PP-{YEAR}-fv05.0.nc

(~12 MB/file, ~25 years, ~300 MB total for the full archive.)

CEDA serves listings as server-rendered HTML with a <tbody id="results"> block;
files download from https://dap.ceda.ac.uk/{path}?download=1.

No authentication is required for these files.

Usage:
  # Fetch a single year
  python tools/esa_permafrost.py --year 2020 --out data/real/esa_permafrost/

  # Fetch a year range
  python tools/esa_permafrost.py --start 2010 --end 2019 --out data/real/esa_permafrost/

  # Fetch all available years
  python tools/esa_permafrost.py --all --out data/real/esa_permafrost/

  # List available years without downloading
  python tools/esa_permafrost.py --list
"""
from __future__ import annotations

import argparse
import re
import sys
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

BASE = "https://data.ceda.ac.uk/neodc/esacci/permafrost/data/permafrost_extent/L4/area4/pp/v05.0/northern_hemisphere"
DL_HOST = "https://dap.ceda.ac.uk"
UA = "CH4-SpaceApps/1.0 (ESA CCI Permafrost fetcher)"

FILE_RE = re.compile(
    r"ESACCI-PERMAFROST-L4-PFR-MODISLST_CRYOGRID-AREA4_PP-(\d{4})-fv05\.0\.nc"
)


class LinkCollector(HTMLParser):
    """Collect href values from a CEDA directory listing."""

    def __init__(self):
        super().__init__()
        self.links: list[str] = []
        self._in_results = False
        self._depth = 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "tbody" and a.get("id") == "results":
            self._in_results = True
            self._depth = 1
            return
        if self._in_results:
            if tag == "tbody":
                self._depth += 1
            if tag == "a" and "href" in a:
                self.links.append(a["href"])

    def handle_endtag(self, tag):
        if self._in_results and tag == "tbody":
            self._depth -= 1
            if self._depth <= 0:
                self._in_results = False


def _get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def list_years() -> list[int]:
    """Return sorted list of year subdirectories found at BASE."""
    html = _get(BASE + "/").decode("utf-8", errors="replace")
    p = LinkCollector()
    p.feed(html)
    years: set[int] = set()
    for href in p.links:
        # Directory links look like .../northern_hemisphere/2020/ or absolute paths
        m = re.search(r"/(\d{4})/?$", href.rstrip("/"))
        if m:
            years.add(int(m.group(1)))
    return sorted(years)


def file_for_year(year: int) -> str | None:
    """Return the .nc filename found in the given year directory, or None."""
    url = f"{BASE}/{year}/"
    try:
        html = _get(url).decode("utf-8", errors="replace")
    except Exception as e:
        print(f"  WARN: failed to list {url}: {e}", file=sys.stderr)
        return None
    p = LinkCollector()
    p.feed(html)
    for href in p.links:
        m = FILE_RE.search(href)
        if m and int(m.group(1)) == year:
            return m.group(0)
    return None


def download_year(year: int, out_dir: Path) -> Path | None:
    name = file_for_year(year)
    if not name:
        print(f"[{year}] no file found", file=sys.stderr)
        return None
    url = f"{DL_HOST}/neodc/esacci/permafrost/data/permafrost_extent/L4/area4/pp/v05.0/northern_hemisphere/{year}/{name}?download=1"
    dest = out_dir / name
    out_dir.mkdir(parents=True, exist_ok=True)

    resume_from = dest.stat().st_size if dest.exists() else 0
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    if resume_from:
        req.add_header("Range", f"bytes={resume_from}-")
    mode = "ab" if resume_from else "wb"

    try:
        with urllib.request.urlopen(req, timeout=180) as r, open(dest, mode) as f:
            total = int(r.headers.get("Content-Length") or 0) + resume_from
            got = resume_from
            while True:
                chunk = r.read(1 << 16)
                if not chunk:
                    break
                f.write(chunk)
                got += len(chunk)
            size = dest.stat().st_size
            tag = "resumed" if resume_from else "ok"
            print(f"[{year}] {tag}: {name}  {size/1e6:.1f} MB")
            return dest
    except urllib.error.HTTPError as e:
        if e.code == 416 and resume_from:
            print(f"[{year}] already complete: {name}  {resume_from/1e6:.1f} MB")
            return dest
        print(f"[{year}] HTTP {e.code}: {e.reason}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"[{year}] error: {e}", file=sys.stderr)
        return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--year", type=int, help="single year to fetch")
    ap.add_argument("--start", type=int, help="start year (inclusive)")
    ap.add_argument("--end", type=int, help="end year (inclusive)")
    ap.add_argument("--all", action="store_true", help="fetch every available year")
    ap.add_argument("--list", action="store_true", help="list available years and exit")
    ap.add_argument("--out", default="data/real/esa_permafrost", help="output directory")
    args = ap.parse_args()

    if args.list:
        years = list_years()
        print(f"Available years ({len(years)}):")
        for y in years:
            print(f"  {y}")
        return

    # Determine target years
    if args.year is not None:
        targets = [args.year]
    elif args.all:
        targets = list_years()
        if not targets:
            print("no years listed at archive", file=sys.stderr)
            sys.exit(1)
    elif args.start is not None and args.end is not None:
        if args.start > args.end:
            ap.error("--start must be <= --end")
        available = set(list_years())
        targets = [y for y in range(args.start, args.end + 1) if y in available]
        if not targets:
            print(f"no archive years in range [{args.start}, {args.end}]", file=sys.stderr)
            sys.exit(1)
    else:
        ap.error("supply --year YYYY, --start/--end, --all, or --list")

    out = Path(args.out)
    ok = 0
    for y in targets:
        if download_year(y, out):
            ok += 1
    print(f"\nDone: {ok}/{len(targets)} files in {out}")


if __name__ == "__main__":
    main()
