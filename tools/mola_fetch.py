#!/usr/bin/env python3
"""mola_fetch.py -- fetch the MOLA MEG128 tile that contains a given (lat, lon).

Replaces the pre-downloaded 124 MB of sample tiles with on-demand retrieval
from the PDS Geosciences Node, which hosts the collection openly (no auth).

The MEG128 collection at 128 ppd is tiled into 44 degree latitude bands x
90 degree longitude stripes, named:
    meg{product}{LL}{hemi}{LLL}hb.{ext}
where
    product = c (counts) | r (radii) | t (topography)
    LL      = NORTH edge latitude of the tile, 2 digits (00, 44, 88)
    hemi    = n (northern)  | s (southern)
    LLL     = WEST edge longitude east, 3 digits (000, 090, 180, 270)
    ext     = img (raw int16 big-endian), hdr (ENVI header),
              lbl (PDS3 label), xml (PDS4 label)

Tile grid verified by parsing the collection inventory and XML labels
(exactly 16 tiles: 4 latitude bands x 4 longitude stripes):
    LL=88n  -> north edge  +88 deg -> covers lat [+44, +88]   (mid north)
    LL=44n  -> north edge  +44 deg -> covers lat [  0, +44]   (equatorial N)
    LL=00n  -> north edge    0 deg -> covers lat [-44,   0]   (equatorial S)
    LL=44s  -> north edge  -44 deg -> covers lat [-88, -44]   (mid south)
    (The polar caps at [+88, +90] and [-90, -88] are NOT part of the MEG128
     grid; they are provided as separate MOLA polar grid products.  This
     fetcher clamps polar queries to the nearest available mid-latitude tile
     and prints a warning.)

    Lon stripes: LLL = 000 -> lon [  0,  90)
                       090 -> lon [ 90, 180)
                       180 -> lon [180, 270)
                       270 -> lon [270, 360)

Each tile is 11520 x 5632 pixels at 128 ppd (~130 MB uncompressed for .img).

Usage:
    python tools\\mola_fetch.py --lat -4.59 --lon 137.44 --product t \
        --out data/real/mars_mola_megdr
    python tools\\mola_fetch.py --lat 18.4 --lon 77.5 --product t --with-labels

Source base URL:
    https://pds-geosciences.wustl.edu/mgs/
        urn-nasa-pds-mgs_mola_topography_derived/meg128/{filename}
"""
from __future__ import annotations
import argparse, sys, urllib.request
from pathlib import Path

BASE = (
    "https://pds-geosciences.wustl.edu/mgs/"
    "urn-nasa-pds-mgs_mola_topography_derived/meg128"
)
PRODUCTS = {"c": "counts", "r": "radii", "t": "topography"}
EXTS_MAIN = ["img", "lbl"]
EXTS_LABELS = ["hdr", "xml"]


def tile_for(lat: float, lon: float) -> tuple[str, str]:
    """Return (lat_prefix, lon_prefix) for the MEG128 tile containing (lat, lon).

    lat in [-90, 90]; lon in [0, 360) east. If lon is negative (west-degrees),
    it is wrapped to east-degrees by taking modulo 360.

    The MEG128 naming encodes the NORTH edge of the tile, not the lower-left
    corner.  The grid has exactly 16 tiles (4 lat bands x 4 lon stripes);
    the lat bands are 44-deg wide: {00n, 44n, 88n, 44s}.  The polar caps
    at |lat| > 88 are NOT in this grid; a warning is printed and the
    nearest band (88n or 44s) is returned.
    """
    if not -90 <= lat <= 90:
        raise ValueError(f"lat must be in [-90, 90], got {lat}")
    lon = lon % 360.0

    # Longitude stripe: 000, 090, 180, 270 -- west edge of a 90-deg stripe.
    lon_ll = (int(lon) // 90) * 90
    lon_pref = f"{lon_ll:03d}"

    # Latitude band keyed by the NORTH edge of the tile.
    if lat > 88:
        print(
            f"  WARNING: lat={lat} is north of the MEG128 grid (max +88).  "
            "Returning the nearest tile (88n); polar coverage requires "
            "the MOLA polar grid product.",
            file=sys.stderr,
        )
        lat_pref = "88n"
    elif lat > 44:
        lat_pref = "88n"        # (+44, +88]  -> north edge = +88
    elif lat > 0:
        lat_pref = "44n"        # (  0, +44]  -> north edge = +44
    elif lat > -44:
        lat_pref = "00n"        # (-44,   0]  -> north edge =   0
    elif lat >= -88:
        lat_pref = "44s"        # [-88, -44]  -> north edge = -44
    else:
        print(
            f"  WARNING: lat={lat} is south of the MEG128 grid (min -88).  "
            "Returning the nearest tile (44s); polar coverage requires "
            "the MOLA polar grid product.",
            file=sys.stderr,
        )
        lat_pref = "44s"
    return lat_pref, lon_pref


def tile_name(product: str, lat_pref: str, lon_pref: str, ext: str) -> str:
    return f"meg{product}{lat_pref}{lon_pref}hb.{ext}"


def head_size(url: str) -> int | None:
    try:
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=30) as r:
            cl = r.headers.get("Content-Length")
            return int(cl) if cl else None
    except Exception:
        return None


def stream_download(url: str, dest: Path, chunk: int = 1 << 16) -> bool:
    resume_from = dest.stat().st_size if dest.exists() else 0
    headers = {}
    if resume_from:
        headers["Range"] = f"bytes={resume_from}-"
    req = urllib.request.Request(url, headers=headers)
    mode = "ab" if resume_from else "wb"
    try:
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
        return True
    except Exception as ex:
        print(f"  FAILED: {ex}", file=sys.stderr)
        return False


def main():
    ap = argparse.ArgumentParser(
        description="Fetch MOLA MEG128 tile(s) that contain a given (lat, lon)."
    )
    ap.add_argument("--lat", type=float, required=True, help="Mars latitude (-90..90)")
    ap.add_argument("--lon", type=float, required=True, help="Mars east longitude (0..360)")
    ap.add_argument(
        "--product", choices=list(PRODUCTS.keys()), default="t",
        help="t=topography (default), c=counts, r=radii",
    )
    ap.add_argument("--out", default="data/real/mars_mola_megdr")
    ap.add_argument("--with-labels", action="store_true",
                    help="Also fetch .hdr and .xml label files (default: just .img + .lbl)")
    ap.add_argument("--list-only", action="store_true",
                    help="Print tile name(s) and URL(s) without downloading")
    args = ap.parse_args()

    lat_pref, lon_pref = tile_for(args.lat, args.lon)
    print(
        f"({args.lat}, {args.lon} E) -> MEG128 tile "
        f"{lat_pref}/{lon_pref}  ({PRODUCTS[args.product]})"
    )

    exts = list(EXTS_MAIN)
    if args.with_labels:
        exts += EXTS_LABELS

    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    for ext in exts:
        name = tile_name(args.product, lat_pref, lon_pref, ext)
        url = f"{BASE}/{name}"
        if args.list_only:
            size = head_size(url)
            size_s = f"{size/1e6:.1f} MB" if size else "?"
            print(f"  {name}  ({size_s})  {url}")
            continue
        dest = out / name
        if dest.exists() and dest.stat().st_size > 0:
            print(f"  {name}: already present ({dest.stat().st_size/1e6:.1f} MB), skipping")
            continue
        print(f"\n> {name}")
        stream_download(url, dest)


if __name__ == "__main__":
    main()
