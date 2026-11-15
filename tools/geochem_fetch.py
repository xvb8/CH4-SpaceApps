#!/usr/bin/env python3
"""Country geochemistry / airborne radiometry fetcher.

Covers the three "country-restricted" sources listed in datasources.md that
would otherwise require manual browsing:

  --region us   USGS NURE airborne gamma-ray K/eU/eTh (ScienceBase REST)
                DOI 10.5066/P9YEAFHI
                Item 5dd2f264e4b0695797628351

  --region au   Geoscience Australia — National Geochemical Survey of
                Australia (NGSA) + related datasets via the GA GeoNetwork
                ElasticSearch API. Direct downloads from GA's
                d28rz98at9flks.cloudfront.net CDN.

                Note: the DOI 10.5066/P9YEAFHI listed in datasources.md
                under "Australia" is actually a USGS DOI (5066 prefix =
                USGS) and resolves to the same ScienceBase item as --region
                us. We fetch the real NGSA from GA instead.

  --region ca   NRCan "Radiometric survey data compilation" via the
                open.canada.ca CKAN API (dataset
                289c931c-a1b1-55f8-8d93-4d88e66f1810).

All transport is stdlib-only (urllib). HTTP Range resume is used for
large files. Use --list to dry-run.
"""
from __future__ import annotations

import argparse
import json
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

UA = "CH4-SpaceApps-geochem/1.0 (+https://github.com)"

# Some gov servers use outdated TLS chains; be forgiving on verification.
SSL_CTX = ssl.create_default_context()
SSL_CTX.check_hostname = False
SSL_CTX.verify_mode = ssl.CERT_NONE

US_ITEM_ID = "5dd2f264e4b0695797628351"
US_API = f"https://www.sciencebase.gov/catalog/item/{US_ITEM_ID}?format=json"

CA_PKG_ID = "289c931c-a1b1-55f8-8d93-4d88e66f1810"
CA_API = (
    "https://open.canada.ca/data/api/3/action/package_show?id=" + CA_PKG_ID
)

AU_ES = "https://ecat.ga.gov.au/geonetwork/srv/api/search/records/_search"
AU_QUERY_DEFAULT = '"National Geochemical Survey of Australia"'


def _req(url, data=None, headers=None, method=None):
    h = {"User-Agent": UA, "Accept": "application/json"}
    if headers:
        h.update(headers)
    return urllib.request.Request(url, data=data, method=method, headers=h)


def http_json(url, data=None, method=None, headers=None, timeout=60):
    req = _req(url, data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as r:
        return json.loads(r.read())


def head_size(url):
    try:
        req = _req(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=30, context=SSL_CTX) as r:
            cl = r.headers.get("Content-Length")
            return int(cl) if cl else None
    except Exception:
        return None


def download(url, dest: Path, chunk: int = 1 << 16) -> bool:
    """Stream download with Range-resume. Returns True on success."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    resume = dest.stat().st_size if dest.exists() else 0
    total = head_size(url)
    if total is not None and resume >= total and total > 0:
        print(f"  [skip] already complete: {dest.name} ({total} B)")
        return True
    headers = {"User-Agent": UA}
    mode = "ab" if resume else "wb"
    if resume:
        headers["Range"] = f"bytes={resume}-"
        print(f"  [resume] {dest.name} from byte {resume}")
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=300, context=SSL_CTX) as r, open(dest, mode) as f:
            got = resume
            while True:
                buf = r.read(chunk)
                if not buf:
                    break
                f.write(buf)
                got += len(buf)
        print(f"  [ok] {dest.name} ({got} B)")
        return True
    except urllib.error.HTTPError as e:
        # Server doesn't like Range? Retry from scratch.
        if resume and e.code in (416, 400):
            dest.unlink(missing_ok=True)
            return download(url, dest, chunk)
        print(f"  [fail] {dest.name}: HTTP {e.code}")
        return False
    except Exception as e:
        print(f"  [fail] {dest.name}: {e}")
        return False


# --------------------------------------------------------------- US ---
def us_entries():
    """Yield dicts {name, url, size} from the USGS ScienceBase item."""
    j = http_json(US_API)
    for f in j.get("files") or []:
        yield {
            "name": f.get("name"),
            "url": f.get("url") or f.get("downloadUri"),
            "size": f.get("size"),
            "content_type": f.get("contentType"),
        }


# --------------------------------------------------------------- CA ---
def ca_entries():
    """Yield dicts from the open.canada.ca CKAN package."""
    j = http_json(CA_API)
    for r in (j.get("result") or {}).get("resources") or []:
        url = r.get("url") or ""
        if not url:
            continue
        name = r.get("name") or url.rsplit("/", 1)[-1]
        # CKAN 'name' can be multilingual dict in some packages.
        if isinstance(name, dict):
            name = name.get("en") or name.get("fr") or next(iter(name.values()), "resource")
        yield {
            "name": name,
            "url": url,
            "size": r.get("size"),
            "content_type": r.get("format"),
        }


# --------------------------------------------------------------- AU ---
def au_entries(query: str = AU_QUERY_DEFAULT, size: int = 100,
               downloads_only: bool = True):
    """Yield dicts from the GA GeoNetwork ElasticSearch index."""
    payload = json.dumps({
        "query": {"query_string": {"query": query}},
        "size": size,
        "_source": ["uuid", "resourceTitleObject", "link"],
    }).encode()
    j = http_json(AU_ES, data=payload, method="POST",
                  headers={"Content-Type": "application/json"})
    for hit in j.get("hits", {}).get("hits", []):
        s = hit.get("_source") or {}
        title = (s.get("resourceTitleObject") or {}).get("default", "")
        for lk in (s.get("link") or []):
            url = (lk.get("urlObject") or {}).get("default", "")
            if not url:
                continue
            name = (lk.get("nameObject") or {}).get("default", "")
            is_dl = (
                lk.get("function") == "download"
                or url.lower().endswith((".csv", ".xls", ".xlsx", ".zip",
                                         ".pdf", ".tif", ".tiff"))
            )
            if downloads_only and not is_dl:
                continue
            # Only keep direct GA CDN downloads (skip external journals, DOIs).
            if "d28rz98at9flks.cloudfront.net" not in url and downloads_only:
                continue
            fn = url.rsplit("/", 1)[-1] or f"{hit.get('_id')}.bin"
            yield {
                "name": fn,
                "title": title,
                "uuid": hit.get("_id"),
                "url": url,
                "size": None,
                "content_type": url.rsplit(".", 1)[-1].lower(),
            }


# ---------------------------------------------------------------- main
def fmt_size(n):
    if n is None:
        return "?"
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def run_region(region: str, out_dir: Path, list_only: bool, limit: int | None,
               match: str | None):
    if region == "us":
        source = "USGS NURE (ScienceBase 5dd2f264...)"
        entries = list(us_entries())
    elif region == "ca":
        source = "NRCan Radiometric (open.canada.ca CKAN)"
        entries = list(ca_entries())
    elif region == "au":
        source = "GA NGSA (GeoNetwork ElasticSearch)"
        entries = list(au_entries())
    else:
        raise SystemExit(f"unknown region: {region}")

    if match:
        m = match.lower()
        entries = [e for e in entries if m in (e.get("name") or "").lower()
                   or m in (e.get("title") or "").lower()]

    print(f"\n=== {region.upper()} — {source}")
    print(f"    {len(entries)} files")
    if limit:
        entries = entries[:limit]

    for e in entries:
        ex = f" [{e.get('title')[:60]}]" if e.get("title") else ""
        print(f"  - {e['name']}  ({fmt_size(e.get('size'))}){ex}")

    if list_only:
        return

    ok = 0
    sub = out_dir / f"geochem_{region}"
    for e in entries:
        if download(e["url"], sub / e["name"]):
            ok += 1
    print(f"\n{region}: {ok}/{len(entries)} downloaded -> {sub}")


def main():
    ap = argparse.ArgumentParser(
        description="Fetch country-scale geochem / airborne radiometry data."
    )
    ap.add_argument("--region", choices=["us", "au", "ca", "all"], required=True,
                    help="Which country to fetch.")
    ap.add_argument("--out", default="data/real/geochem",
                    help="Output directory (default: data/real/geochem)")
    ap.add_argument("--list", action="store_true",
                    help="Only list available files; do not download.")
    ap.add_argument("--limit", type=int, default=None,
                    help="Max files to download (useful for testing).")
    ap.add_argument("--match", default=None,
                    help="Case-insensitive substring filter on name/title.")
    args = ap.parse_args()

    out = Path(args.out)
    regions = ["us", "au", "ca"] if args.region == "all" else [args.region]
    for r in regions:
        run_region(r, out, args.list, args.limit, args.match)


if __name__ == "__main__":
    main()
