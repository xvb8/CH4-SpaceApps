#!/usr/bin/env python3
"""tropomi_finhub.py -- fetch the most recent TROPOMI products from FMI finhub.

finhub.nsdc.fmi.fi is a DHuS (Data Hub Service) instance run by FMI that
mirrors Sentinel-5P TROPOMI products for the Nordic / northern-hemisphere
region.  It uses the same OpenSearch + OData API as Copernicus SciHub, with
HTTP Basic auth.

Register for a free account at https://finhub.nsdc.fmi.fi/#/self-registration
and set credentials via:
    set FINHUB_USER=<your_user>
    set FINHUB_PASS=<your_pass>

Products of interest for the "surface UV" and permafrost / high-latitude
atmosphere use cases:
    L2__O3____ (ozone column)
    L2__NO2___ (nitrogen dioxide)
    L2__SO2___ (sulphur dioxide)
    L2__CO____ (carbon monoxide)
    L2__CH4___ (methane)
    L2__AER_AI (aerosol index -- proxy for surface UV attenuation)
    L2__CLOUD_ (cloud properties -- modulates UV at the surface)

By default this script filters to the northern hemisphere (lat >= 0) using
an OpenSearch polygon footprint filter and sorts by ingestion date desc,
so the N most recent files are returned.

Usage:
    python tools\\tropomi_finhub.py --product L2__AER_AI --count 5
    python tools\\tropomi_finhub.py --product L2__O3____ --count 10 \
        --out data/real/tropomi
    python tools\\tropomi_finhub.py --list-products
"""
from __future__ import annotations
import argparse, base64, json, os, sys, urllib.parse, urllib.request
from pathlib import Path
from xml.etree import ElementTree as ET

BASE = "https://finhub.nsdc.fmi.fi"
# Northern hemisphere polygon (full ring, lon in [-180, 180], lat 0..90).
# DHuS OpenSearch expects WKT "POLYGON((lon lat, ...))".
NORTH_POLY = "POLYGON((-180 0, 180 0, 180 90, -180 90, -180 0))"

# Common Sentinel-5P / TROPOMI product type codes.
PRODUCT_TYPES = [
    "L2__O3____", "L2__NO2___", "L2__SO2___", "L2__CO____", "L2__CH4___",
    "L2__HCHO__", "L2__AER_AI", "L2__AER_LH", "L2__CLOUD_",
    "L1B_RA_BD1", "L1B_RA_BD2", "L1B_RA_BD3", "L1B_RA_BD4",
    "L1B_RA_BD5", "L1B_RA_BD6", "L1B_RA_BD7", "L1B_RA_BD8",
]

NS = {
    "a":   "http://www.w3.org/2005/Atom",
    "os":  "http://a9.com/-/spec/opensearch/1.1/",
}


def creds() -> tuple[str, str]:
    u = os.environ.get("FINHUB_USER")
    p = os.environ.get("FINHUB_PASS")
    if not u or not p:
        raise SystemExit(
            "ERROR: FINHUB_USER / FINHUB_PASS env vars not set.  "
            "Register at https://finhub.nsdc.fmi.fi/#/self-registration "
            "then set:\n"
            "    set FINHUB_USER=<your_user>\n"
            "    set FINHUB_PASS=<your_pass>"
        )
    return u, p


def auth_header() -> dict:
    u, p = creds()
    tok = base64.b64encode(f"{u}:{p}".encode()).decode()
    return {"Authorization": f"Basic {tok}"}


def opensearch(query: str, rows: int = 10, start: int = 0) -> list[dict]:
    """Run an OpenSearch query against finhub and return parsed entries.

    Each returned dict has: id, title, ingestion_date, size, footprint,
    product_type, download_url, quicklook_url.
    """
    params = {
        "q": query,
        "rows": rows,
        "start": start,
        "orderby": "ingestiondate desc",
        "format": "xml",
    }
    url = f"{BASE}/search?{urllib.parse.urlencode(params)}"
    print(f"\nGET {url}", file=sys.stderr)
    req = urllib.request.Request(url, headers=auth_header())
    with urllib.request.urlopen(req, timeout=60) as r:
        body = r.read()

    root = ET.fromstring(body)
    entries = []
    for e in root.findall("a:entry", NS):
        d = {
            "id":    (e.findtext("a:id", default="", namespaces=NS) or "").strip(),
            "title": (e.findtext("a:title", default="", namespaces=NS) or "").strip(),
        }
        # DHuS stores most metadata in <str name="...">value</str>,
        # <date name="...">...</date>, <int name="...">...</int>.
        for tag, attr in [("str", "name"), ("date", "name"), ("int", "name")]:
            for kv in e.findall(f"{{http://www.w3.org/2005/Atom}}{tag}"):
                d[kv.get(attr)] = kv.text
        # Download link is the <link rel="alternative"> or href on the entry.
        for link in e.findall("a:link", NS):
            if link.get("rel") is None and link.get("href", "").endswith("/$value"):
                d["download_url"] = link.get("href")
            if link.get("rel") == "icon":
                d["quicklook_url"] = link.get("href")
        if "download_url" not in d:
            d["download_url"] = f"{BASE}/odata/v1/Products('{d['id']}')/$value"
        entries.append(d)
    return entries


def build_query(product_type: str | None, bbox: str | None,
                extra: str | None) -> str:
    parts = ["platformname:Sentinel-5"]
    if product_type:
        parts.append(f'producttype:{product_type}')
    if bbox:
        parts.append(f'footprint:"Intersects({bbox})"')
    if extra:
        parts.append(f"({extra})")
    return " AND ".join(parts)


def stream_download(url: str, dest: Path, chunk: int = 1 << 16) -> bool:
    resume_from = dest.stat().st_size if dest.exists() else 0
    hdrs = dict(auth_header())
    if resume_from:
        hdrs["Range"] = f"bytes={resume_from}-"
    req = urllib.request.Request(url, headers=hdrs)
    mode = "ab" if resume_from else "wb"
    try:
        with urllib.request.urlopen(req, timeout=180) as r, open(dest, mode) as f:
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
                    print(
                        f"\r  {dest.name}: {read/1e6:.1f} / {total_i/1e6:.1f} MB ({pct:.1f}%)",
                        end="", flush=True,
                    )
            print()
        return True
    except Exception as ex:
        print(f"  FAILED: {ex}", file=sys.stderr)
        return False


def main():
    ap = argparse.ArgumentParser(
        description="Fetch most-recent TROPOMI products from FMI finhub."
    )
    ap.add_argument("--product", default="L2__AER_AI",
                    help=f"Product type (default: L2__AER_AI).  "
                         f"Known codes: {', '.join(PRODUCT_TYPES)}")
    ap.add_argument("--count", type=int, default=5,
                    help="How many most-recent products to fetch (default 5)")
    ap.add_argument("--bbox", default=NORTH_POLY,
                    help="WKT polygon footprint filter "
                         "(default: full northern hemisphere)")
    ap.add_argument("--extra", default=None,
                    help="Extra OpenSearch query clauses (e.g. "
                         "'beginposition:[NOW-7DAYS TO NOW]')")
    ap.add_argument("--out", default="data/real/tropomi",
                    help="Destination directory for downloaded .nc files")
    ap.add_argument("--list-only", action="store_true",
                    help="Only list matching products; do not download")
    ap.add_argument("--list-products", action="store_true",
                    help="Print the TROPOMI product-type codes and exit")
    args = ap.parse_args()

    if args.list_products:
        print("TROPOMI product-type codes:")
        for p in PRODUCT_TYPES:
            print(f"  {p}")
        return

    q = build_query(args.product, args.bbox, args.extra)
    print(f"Query: {q}", file=sys.stderr)
    entries = opensearch(q, rows=args.count)
    print(f"\nFound {len(entries)} product(s):")
    for i, e in enumerate(entries, 1):
        size = e.get("size") or "?"
        ing  = e.get("ingestiondate") or e.get("beginposition") or "?"
        print(f"  [{i}] {e['title']}")
        print(f"       ingested {ing}  size {size}")
        print(f"       -> {e['download_url']}")

    if args.list_only or not entries:
        return

    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    for i, e in enumerate(entries, 1):
        name = f"{e['title']}.nc"
        dest = out / name
        if dest.exists() and dest.stat().st_size > 0:
            print(f"\n[{i}/{len(entries)}] {name}: already present "
                  f"({dest.stat().st_size/1e6:.1f} MB), skipping")
            continue
        print(f"\n[{i}/{len(entries)}] > {name}")
        stream_download(e["download_url"], dest)


if __name__ == "__main__":
    main()
