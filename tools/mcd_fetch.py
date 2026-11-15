#!/usr/bin/env python3
"""
Mars Climate Database (MCD v6.2) HTTP fetcher.

Queries http://www-mars.lmd.jussieu.fr/mcd_python/cgi-bin/mcdcgi.py as a
point-sampling API.  The MCD web interface only supports point queries; to
build a grid, we call it per cell and assemble the results.

Variables (common ones; see listvar.js on the server for the full list):
  t             Temperature (K)
  tsurf         Surface temperature (K)
  p             Pressure (Pa)
  ps            Surface pressure (Pa)
  rho           Density (kg/m3)
  wind          Horizontal wind speed (m/s)
  col_h2ovapor  Water vapor column (kg/m2)
  vmr_h2o       Water vapor vol. mixing ratio (mol/mol)
  tauref        Daily mean dust column visible optical depth
  fluxsurf_dn_sw  Incident solar flux on horizontal surface (W/m2)
  oroheight     Orographic height (m)
  thermal_inertia GCM surface thermal inertia
  ground_albedo GCM surface bare ground albedo

Zkey (altitude reference):
  2 = altitude above areoid (Mars geoid)
  3 = altitude above local surface (ALS)
  4 = pressure level (Pa)

Dust scenarios:
  1 = climatology average solar scenario (default)
  2 = cold / low dust
  3 = warm / high dust
  ...

Usage:
  # single-point sample
  python tools/mcd_fetch.py --point 18.4 77.5 --var tsurf --ls 90
  # with altitude 10 m above local surface, local time noon
  python tools/mcd_fetch.py --point 18.4 77.5 --var t --ls 90 --localtime 12 --alt 10

  # regular grid, saved to CSV
  python tools/mcd_fetch.py --grid --latstep 10 --lonstep 20 \\
      --var tsurf --ls 90 --localtime 12 --out data/real/mcd/tsurf_ls090_lt12.csv

  # multiple variables at once (up to 4)
  python tools/mcd_fetch.py --point 18.4 77.5 \\
      --var tsurf --var ps --var col_h2ovapor --ls 90
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ENDPOINT = "http://www-mars.lmd.jussieu.fr/mcd_python/cgi-bin/mcdcgi.py"
UA = "CH4-SpaceApps/1.0 (MCD fetcher)"

# Response line parser. Example:
#   Temperature (K) ..... 205.09537
RESULT_RE = re.compile(r"<li>\s*(.+?)\s*\.{2,}\s*(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)")


def query(
    variables: list[str],
    lat: float,
    lon: float,
    *,
    ls: float = 0.0,
    localtime: float = 0.0,
    altitude: float = 10.0,
    zkey: int = 3,
    dust: int = 1,
    hrkey: int = 1,
    isfixedlt: bool = True,
) -> dict[str, float]:
    """Issue one point query; return {label: value}.

    - variables: up to 4 MCD variable short names (see docstring).
    - lat, lon: Mars coordinates (deg).
    - ls: solar longitude (0-360).
    - localtime: local true solar time in hours (0-24).
    - altitude: elevation in units determined by zkey.
    - zkey: 2=above areoid, 3=above local surface, 4=pressure level.
    - dust: scenario id (1 = climatology average).
    - hrkey: 1 to use the high-resolution MCD mode, 0 for GCM-only.
    - isfixedlt: if True, time is fixed local time (fair daily snapshot).
    """
    if not variables:
        raise ValueError("at least one variable required")
    if len(variables) > 4:
        raise ValueError("MCD supports at most 4 variables per query")
    params = {
        "var1": variables[0],
        "var2": variables[1] if len(variables) > 1 else "none",
        "var3": variables[2] if len(variables) > 2 else "none",
        "var4": variables[3] if len(variables) > 3 else "none",
        "datekeyhtml": "1",
        "ls": f"{ls:.3f}",
        "localtime": f"{localtime:.3f}",
        "latitude": f"{lat:.6f}",
        "longitude": f"{lon:.6f}",
        "altitude": f"{altitude:.3f}",
        "zkey": str(zkey),
        "isfixedlt": "on" if isfixedlt else "off",
        "dust": str(dust),
        "hrkey": str(hrkey),
        "proj": "cyl",
        "colorm": "jet",
        "dpi": "80",
    }
    url = ENDPOINT + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        html = r.read().decode("utf-8", errors="replace")
    out: dict[str, float] = {}
    for m in RESULT_RE.finditer(html):
        label = m.group(1).strip()
        try:
            out[label] = float(m.group(2))
        except ValueError:
            continue
    if not out:
        raise RuntimeError(f"MCD returned no parseable values. URL: {url}\n---\n{html[-800:]}")
    return out


def frange(start: float, stop: float, step: float) -> list[float]:
    """Inclusive arange that avoids float drift for grid building."""
    if step <= 0:
        raise ValueError("step must be > 0")
    n = int(round((stop - start) / step)) + 1
    return [round(start + i * step, 6) for i in range(n)]


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--point", nargs=2, type=float, metavar=("LAT", "LON"),
        help="single point query"
    )
    mode.add_argument(
        "--grid", action="store_true",
        help="sample a regular lat-lon grid (uses --latmin/--latmax/--latstep etc.)"
    )
    ap.add_argument("--var", action="append", required=True,
                    help="MCD variable short name (may be repeated, up to 4)")
    ap.add_argument("--ls", type=float, default=0.0, help="solar longitude (deg)")
    ap.add_argument("--localtime", type=float, default=12.0, help="local solar time (hr)")
    ap.add_argument("--alt", type=float, default=10.0, help="altitude in zkey units")
    ap.add_argument("--zkey", type=int, default=3, choices=[2, 3, 4],
                    help="2=areoid, 3=above local surface (default), 4=pressure level")
    ap.add_argument("--dust", type=int, default=1, help="dust scenario (1=clim avg)")
    ap.add_argument("--hrkey", type=int, default=1, choices=[0, 1],
                    help="1=high-res mode (default), 0=GCM only")
    ap.add_argument("--latmin", type=float, default=-90.0)
    ap.add_argument("--latmax", type=float, default=90.0)
    ap.add_argument("--latstep", type=float, default=10.0)
    ap.add_argument("--lonmin", type=float, default=-180.0)
    ap.add_argument("--lonmax", type=float, default=180.0)
    ap.add_argument("--lonstep", type=float, default=20.0)
    ap.add_argument("--delay", type=float, default=0.2,
                    help="seconds between grid requests to be polite")
    ap.add_argument("--out", type=Path, help="output CSV (grid mode) or JSON (point mode)")
    args = ap.parse_args()

    if len(args.var) > 4:
        ap.error("MCD supports at most 4 variables per query (--var repeated)")

    if args.point is not None:
        lat, lon = args.point
        vals = query(
            args.var, lat, lon,
            ls=args.ls, localtime=args.localtime, altitude=args.alt,
            zkey=args.zkey, dust=args.dust, hrkey=args.hrkey,
        )
        print(f"MCD point (lat={lat}, lon={lon}, Ls={args.ls}, LT={args.localtime}h):")
        for label, v in vals.items():
            print(f"  {label}: {v}")
        if args.out:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            import json
            args.out.write_text(json.dumps({
                "lat": lat, "lon": lon, "ls": args.ls, "localtime": args.localtime,
                "altitude": args.alt, "zkey": args.zkey, "dust": args.dust,
                "values": vals,
            }, indent=2))
            print(f"\nWrote {args.out}")
        return

    # Grid mode
    lats = frange(args.latmin, args.latmax, args.latstep)
    lons = frange(args.lonmin, args.lonmax, args.lonstep)
    total = len(lats) * len(lons)
    print(f"Grid: {len(lats)} x {len(lons)} = {total} cells "
          f"(Ls={args.ls}, LT={args.localtime}h, vars={args.var})")
    if not args.out:
        print("ERROR: --out is required for --grid", file=sys.stderr)
        sys.exit(1)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    with open(args.out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        # Header: lat, lon, then one column per returned label
        header_written = False
        labels: list[str] = []
        done = 0
        for lat in lats:
            for lon in lons:
                try:
                    vals = query(
                        args.var, lat, lon,
                        ls=args.ls, localtime=args.localtime, altitude=args.alt,
                        zkey=args.zkey, dust=args.dust, hrkey=args.hrkey,
                    )
                except Exception as e:
                    print(f"  [{lat},{lon}] ERROR: {e}", file=sys.stderr)
                    vals = {}
                if not header_written:
                    labels = list(vals.keys()) if vals else [f"var{i+1}" for i in range(len(args.var))]
                    w.writerow(["lat", "lon", *labels])
                    header_written = True
                row = [lat, lon] + [vals.get(lab, "") for lab in labels]
                w.writerow(row)
                done += 1
                if done % 10 == 0 or done == total:
                    print(f"  {done}/{total}")
                if args.delay > 0:
                    time.sleep(args.delay)
    print(f"\nWrote {args.out}")


if __name__ == "__main__":
    main()
