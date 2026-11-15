#!/usr/bin/env python3
"""copernicus_dem.py -- fetch Copernicus DEM GLO-30 tiles by location.

Uses the Copernicus Data Space Ecosystem (CDSE) OData catalogue + download API
documented at https://dataspace.copernicus.eu/analyse/apis — no vendor libs.

Two steps:

1. SEARCH (unauthenticated):
     GET https://catalogue.dataspace.copernicus.eu/odata/v1/Products
     ?$filter=contains(Name,'DEM1_SAR_DGE_30') and
             OData.CSC.Intersects(area=geography'SRID=4326;POINT(<lon> <lat>)')
     &$top=10

2. DOWNLOAD (Keycloak token):
     POST https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/
          openid-connect/token
          grant_type=password & client_id=cdse-public
          & username=<email> & password=<password>
     -> {"access_token": "<jwt>", ...}

     GET https://catalogue.dataspace.copernicus.eu/odata/v1/Products(<id>)/$value
         -H "Authorization: Bearer <jwt>"

Each DEM product file is a 1x1 degree tile (~50-110 MB) in the DGED format.

Usage:
    set CDSE_USER=you@example.com
    set CDSE_PASS=yourpassword
    python tools\\copernicus_dem.py --lat 46.5 --lon 10.5 --out data/real/earth_copdem_glo30

    # Dry run (no credentials required):
    python tools\\copernicus_dem.py --lat 46.5 --lon 10.5 --list-only
"""
from __future__ import annotations
import argparse, json, os, sys, urllib.parse, urllib.request
from pathlib import Path

ODATA = "https://catalogue.dataspace.copernicus.eu/odata/v1/Products"
TOKEN_URL = (
    "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/"
    "protocol/openid-connect/token"
)
DEM_NAME_PREFIX = "DEM1_SAR_DGE_30"  # GLO-30 DGED tiles


def odata_search(lat: float, lon: float, top: int = 10):
    """Return a list of product dicts whose footprint contains (lat, lon)."""
    filt = (
        f"contains(Name,'{DEM_NAME_PREFIX}') and "
        f"OData.CSC.Intersects(area=geography'SRID=4326;POINT({lon} {lat})')"
    )
    qs = urllib.parse.urlencode({"$filter": filt, "$top": str(top)})
    req = urllib.request.Request(ODATA + "?" + qs, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r).get("value", [])


def cdse_token(username: str, password: str) -> str:
    body = urllib.parse.urlencode({
        "grant_type": "password",
        "client_id": "cdse-public",
        "username": username,
        "password": password,
    }).encode("utf-8")
    req = urllib.request.Request(
        TOKEN_URL,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["access_token"]


def download(product_id: str, dest: Path, token: str, chunk: int = 1 << 16):
    url = f"{ODATA}({product_id})/$value"
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
                print(
                    f"\r  {dest.name}: {read/1e6:.1f} / {total_i/1e6:.1f} MB ({pct:.1f}%)",
                    end="", flush=True,
                )
        print()


def main():
    ap = argparse.ArgumentParser(description="Fetch Copernicus DEM GLO-30 tile(s) by lat/lon.")
    ap.add_argument("--lat", type=float, required=True)
    ap.add_argument("--lon", type=float, required=True)
    ap.add_argument("--out", default="data/real/earth_copdem_glo30")
    ap.add_argument("--max", type=int, default=1, help="Max tiles to download (default 1)")
    ap.add_argument("--list-only", action="store_true")
    args = ap.parse_args()

    products = odata_search(args.lat, args.lon, top=max(args.max, 1))
    print(f"Found {len(products)} DEM tile(s) containing ({args.lat}, {args.lon})")
    for p in products:
        print(f"  {p['Id']}  {p['Name']}  ({p['ContentLength']/1e6:.1f} MB)")
    if args.list_only or not products:
        return

    user = os.environ.get("CDSE_USER", "").strip()
    pw = os.environ.get("CDSE_PASS", "").strip()
    if not (user and pw):
        print(
            "ERROR: set CDSE_USER and CDSE_PASS env vars "
            "(free account at https://dataspace.copernicus.eu/)",
            file=sys.stderr,
        )
        sys.exit(2)

    print("Authenticating with CDSE Keycloak ...")
    token = cdse_token(user, pw)
    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)

    for p in products[: args.max]:
        name = p["Name"]
        if not name.lower().endswith(".dem"):
            name += ".DEM"
        dest = out / name
        print(f"\n> {name}")
        try:
            download(p["Id"], dest, token)
        except Exception as ex:
            print(f"  FAILED: {ex}", file=sys.stderr)


if __name__ == "__main__":
    main()
