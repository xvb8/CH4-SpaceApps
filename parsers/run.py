"""Parse real data for any location(s).

    python -m parsers.run --lat 18.44 --lon 77.45 --radius 50
    python -m parsers.run --locations data/mars_regions.json --out parsed_mars.csv
    python -m parsers.run --locations sites.csv --datasets grs caves
    python -m parsers.run --planet earth --locations data/earth_sites.json --out parsed_earth.csv

--locations accepts:
  * JSON shaped like data/mars_regions.json ({"regions": [{"name", "lat", "lon"}]})
    or data/earth_sites.json ({"sites": [...]}), or a plain list of such objects
  * CSV with name, lat, lon columns
Longitude may be 0-360 or -180..180. Missing data is written as blank (None),
never 0. Datasets whose files are not present are skipped with a message.

--criteria-out writes a second CSV whose columns are the criterion names used by
analog_scoring.py / chemical_composition.py (see parsers/criteria.py).
"""

import argparse
import csv
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

DATASETS = {
    "mars": ["grs", "gullies", "caves", "mola", "mcs"],
    "earth": ["icewedge", "permafrost", "power", "earth_chem"],
}
ALL_DATASETS = sorted({d for v in DATASETS.values() for d in v})


def load_dataset(name):
    if name == "grs":
        from parsers.grs import GRS
        return GRS()
    if name == "gullies":
        from parsers.gullies import Gullies
        return Gullies()
    if name == "caves":
        from parsers.caves import Caves
        return Caves()
    if name == "mola":
        from parsers.mola import MOLA
        return MOLA()
    if name == "mcs":
        from parsers.mcs import MCS
        return MCS()
    if name == "icewedge":
        from parsers.icewedge import IceWedge
        return IceWedge()
    if name == "permafrost":
        from parsers.permafrost import Permafrost
        return Permafrost()
    if name == "power":
        from parsers.power import Power
        return Power()
    if name == "earth_chem":
        from parsers.earth_chem import EarthChem
        return EarthChem()
    raise KeyError(name)


def read_locations(path):
    if path.lower().endswith(".json"):
        with open(path) as f:
            data = json.load(f)
        if isinstance(data, dict):
            data = data.get("regions") or data.get("sites") or data.get("locations") or []
        return [(d["name"], float(d["lat"]), float(d["lon"])) for d in data]
    with open(path, newline="") as f:
        return [(r["name"], float(r["lat"]), float(r["lon"])) for r in csv.DictReader(f)]


def parse(locations, datasets=DATASETS["mars"], radius_km=50):
    """Return [{'name', 'lat', 'lon', <value columns>...}] for every location."""
    loaded = {}
    for name in datasets:
        try:
            loaded[name] = load_dataset(name)
        except (FileNotFoundError, OSError) as e:
            print(f"[{name}] skipped: data not found ({e})", file=sys.stderr)
    rows = []
    for loc_name, lat, lon in locations:
        row = {"name": loc_name, "lat": lat, "lon": lon}
        for ds in loaded.values():
            row.update(ds.query(lat, lon, radius_km))
        rows.append(row)
    return rows


def write_csv(rows, path):
    cols = list(dict.fromkeys(k for r in rows for k in r))
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows({k: ("" if r.get(k) is None else r.get(k)) for k in cols} for r in rows)
    return len(cols) - 3


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lat", type=float)
    ap.add_argument("--lon", type=float)
    ap.add_argument("--name", default="point")
    ap.add_argument("--locations", help="JSON or CSV of locations (name, lat, lon)")
    ap.add_argument("--radius", type=float, default=50, help="search radius in km (default 50)")
    ap.add_argument("--planet", choices=sorted(DATASETS), default="mars")
    ap.add_argument("--datasets", nargs="+", choices=ALL_DATASETS,
                    help="default: every dataset for --planet")
    ap.add_argument("--out", help="write CSV here (default: print)")
    ap.add_argument("--criteria-out", help="also write criterion-named values here")
    args = ap.parse_args(argv)

    if args.locations:
        locations = read_locations(args.locations)
    elif args.lat is not None and args.lon is not None:
        locations = [(args.name, args.lat, args.lon)]
    else:
        ap.error("give --lat and --lon, or --locations")

    rows = parse(locations, args.datasets or DATASETS[args.planet], args.radius)
    if args.out:
        n = write_csv(rows, args.out)
        print(f"wrote {len(rows)} locations x {n} values to {args.out}")
    if args.criteria_out:
        from parsers.criteria import to_criteria
        crit = [{"name": r["name"], "lat": r["lat"], "lon": r["lon"], **to_criteria(r)} for r in rows]
        n = write_csv(crit, args.criteria_out)
        print(f"wrote {len(rows)} locations x {n} criteria to {args.criteria_out}")
    if not args.out and not args.criteria_out:
        for r in rows:
            print(json.dumps(r))
    return rows


if __name__ == "__main__":
    main()
