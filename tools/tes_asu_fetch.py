#!/usr/bin/env python3
"""
TES (Mars Global Surveyor / Thermal Emission Spectrometer) Global Data Maps
fetcher via the ASU JMars WMS endpoint.

Source: https://mars.asu.edu/data/  (Mars Global Data Sets)
WMS:    http://ms-mars.mars.asu.edu/{LAYER}?SERVICE=WMS&REQUEST=GetMap&...

Each product has:
  - A PNG rendering (visual map)
  - A VICAR raw-numeric variant for scientifically meaningful layers (e.g.
    TES_Thermal_Inertia_numeric)

The WMS endpoint supports arbitrary BBOX / WIDTH / HEIGHT, so this script is
effectively an on-demand tile/global cutter -- no bulk download required.

Usage:
  # List supported layers
  python tools/tes_asu_fetch.py --list

  # Global PNG @ full 8ppd resolution
  python tools/tes_asu_fetch.py --layer TES_Thermal_Inertia --out data/real/tes/

  # Global raw numeric VICAR
  python tools/tes_asu_fetch.py --layer TES_Thermal_Inertia_numeric \
      --format vicar --out data/real/tes/

  # Regional crop around Jezero (lat/lon in degrees east)
  python tools/tes_asu_fetch.py --layer TES_Albedo \
      --bbox -5 25 70 90 --width 800 --height 600 --out data/real/tes/
"""
from __future__ import annotations

import argparse
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ENDPOINT = "http://ms-mars.mars.asu.edu/"
UA = "CH4-SpaceApps/1.0 (TES ASU WMS fetcher)"

# Layer catalog -- (layer_id, suggested filename ext, description)
LAYERS = {
    # Thermal inertia
    "TES_Thermal_Inertia":         ("TES thermal inertia (Christensen et al. 2001), 8ppd/7.5km"),
    "TES_Thermal_Inertia_mola":    ("TES thermal inertia blended with MOLA shaded relief"),
    "TES_Thermal_Inertia_numeric": ("TES thermal inertia (raw numeric values) -- use --format vicar"),
    # Albedo
    "TES_Albedo":                  ("TES broadband bolometric albedo (Christensen et al.)"),
    "TES_Albedo_mola":             ("TES albedo + MOLA shade"),
    # Dust
    "TES_Dust_Index":              ("TES surface dust cover index (Ruff & Christensen 2002)"),
    "TES_Dust_Index_mola":         ("TES dust index + MOLA shade"),
    # Hematite
    "TES_Hematite":                ("TES crystalline hematite abundance (Christensen et al.)"),
    "TES_Hematite_mola":           ("TES hematite + MOLA shade"),
    # Minerals (Bandfield et al.)
    "TES_Olivine":                 ("TES olivine abundance (Bandfield 2002)"),
    "TES_Clinopyroxene":           ("TES clinopyroxene abundance"),
    "TES_Orthopyroxene":           ("TES orthopyroxene abundance"),
    "TES_Plagioclase":             ("TES plagioclase abundance"),
    "TES_KFeldspar":               ("TES K-feldspar abundance"),
    # Putzig TI
    "TES_Putzig_TI_Nighttime":     ("Putzig night-time TES thermal inertia"),
    "TES_Putzig_TI_Dayside_2007":  ("Putzig dayside 2007 TI"),
    "TES_Putzig_TI_Nightside_2007":("Putzig nightside 2007 TI"),
}

FORMAT_MAP = {
    "png":   ("image/png", ".png"),
    "jpeg":  ("image/jpeg", ".jpg"),
    "vicar": ("image/vicar", ".vicar"),
    "tiff":  ("image/tiff", ".tif"),
}


def build_url(layer: str, fmt_mime: str, width: int, height: int, bbox):
    params = {
        "SERVICE": "WMS",
        "REQUEST": "GetMap",
        "VERSION": "1.1.1",
        "FORMAT": fmt_mime,
        "WIDTH": width,
        "HEIGHT": height,
        "SRS": "JMARS:4",
        "BBOX": f"{bbox[2]},{bbox[0]},{bbox[3]},{bbox[1]}",  # wlon,minlat,elon,maxlat
        "STYLES": "",
        "LAYERS": layer,
    }
    # Note: ms-mars WMS rejects percent-encoded slashes in FORMAT (e.g.
    # "image%2Fpng"), so we build the query string manually and keep
    # "/", ",", and ":" unescaped.
    parts = []
    for k, v in params.items():
        key_enc = urllib.parse.quote(str(k), safe="")
        val_enc = urllib.parse.quote(str(v), safe="/,:")
        parts.append(f"{key_enc}={val_enc}")
    return ENDPOINT + layer + "?" + "&".join(parts)


def download(url: str, dest: Path) -> int:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=300) as r, open(dest, "wb") as f:
        total = 0
        while True:
            buf = r.read(1 << 16)
            if not buf:
                break
            f.write(buf)
            total += len(buf)
    return total


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--layer", help="Layer id (see --list)")
    p.add_argument("--list", action="store_true", help="List available layers and exit")
    p.add_argument("--format", choices=sorted(FORMAT_MAP), default="png",
                   help="Output format (png/jpeg/vicar/tiff)")
    p.add_argument("--bbox", type=float, nargs=4, metavar=("MINLAT", "MAXLAT", "WLON", "ELON"),
                   default=[-90, 90, -180, 180],
                   help="Bounding box (degrees east). Default: global.")
    p.add_argument("--width",  type=int, default=2880, help="Output width in pixels (default 2880)")
    p.add_argument("--height", type=int, default=1440, help="Output height in pixels (default 1440)")
    p.add_argument("--out", type=Path, help="Output directory")
    p.add_argument("--filename", help="Override output filename")
    args = p.parse_args()

    if args.list:
        print(f"{len(LAYERS)} TES ASU layers:")
        for name, desc in LAYERS.items():
            print(f"  {name:36s} {desc}")
        return 0

    if not args.layer:
        p.error("--layer is required (or use --list)")
    if args.layer not in LAYERS:
        print(f"WARNING: layer '{args.layer}' not in known catalog (will try anyway)", file=sys.stderr)
    if args.out is None:
        p.error("--out is required unless --list")

    mime, ext = FORMAT_MAP[args.format]
    url = build_url(args.layer, mime, args.width, args.height, args.bbox)
    fname = args.filename or f"{args.layer}_{args.width}x{args.height}{ext}"
    dest = args.out / fname

    print(f"GET {url}")
    size = download(url, dest)
    print(f"  -> {dest} ({size/1e6:.2f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
