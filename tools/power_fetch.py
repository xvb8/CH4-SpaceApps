#!/usr/bin/env python3
"""Fetch NASA POWER monthly climatology for every Earth site.

No authentication required. One JSON per site is written under
data/real/nasa_power/<id>.json. The JSON contains monthly and annual
means of T2M, T2M_MAX, T2M_MIN (deg C) and `geometry.coordinates[2]`
which is the site elevation in metres (bonus, we use it later).

    python tools/power_fetch.py
    python tools/power_fetch.py --sites data/earth_sites.json
    python tools/power_fetch.py --force      # re-download everything
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

ENDPOINT = (
    "https://power.larc.nasa.gov/api/temporal/climatology/point"
    "?parameters=T2M,T2M_MAX,T2M_MIN&community=RE"
    "&latitude={lat}&longitude={lon}&format=JSON"
)
DEFAULT_SITES = "data/earth_sites.json"
DEFAULT_OUT = "data/real/nasa_power"
UA = "CH4-SpaceApps/1.0 (NASA Space Apps analog finder)"


def load_sites(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    sites = data.get("sites") if isinstance(data, dict) else data
    out = []
    for s in sites or []:
        try:
            out.append((s["id"], s["name"], float(s["lat"]), float(s["lon"])))
        except (KeyError, TypeError, ValueError):
            continue
    return out


def fetch_point(lat, lon, retries=3, timeout=90):
    url = ENDPOINT.format(lat=lat, lon=lon)
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError) as e:
            last = e
            time.sleep(1.5 * (i + 1))
    raise RuntimeError(f"POWER fetch failed for {lat},{lon}: {last}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sites", default=DEFAULT_SITES)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--force", action="store_true", help="overwrite existing files")
    ap.add_argument("--sleep", type=float, default=0.2, help="delay between requests (s)")
    args = ap.parse_args(argv)

    os.makedirs(args.out, exist_ok=True)
    sites = load_sites(args.sites)
    print(f"[power] {len(sites)} sites from {args.sites}", file=sys.stderr)

    ok = skipped = failed = 0
    for sid, name, lat, lon in sites:
        dest = os.path.join(args.out, f"{sid}.json")
        if os.path.exists(dest) and not args.force:
            skipped += 1
            continue
        try:
            data = fetch_point(lat, lon)
            with open(dest, "w", encoding="utf-8") as f:
                json.dump(data, f)
            ok += 1
            print(f"  [ok]   {sid:<14s} {name}", file=sys.stderr)
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"  [fail] {sid:<14s} {name}: {e}", file=sys.stderr)
        time.sleep(args.sleep)

    print(f"[power] ok={ok} skipped={skipped} failed={failed}", file=sys.stderr)


if __name__ == "__main__":
    main()
