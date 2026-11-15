"""Earth climate + elevation from NASA POWER monthly climatology.

Reads per-site JSON files produced by `python tools/power_fetch.py`
(stored under data/real/nasa_power/<id>.json). For a (lat, lon) query
it picks the closest cached site and returns Mars-comparable criteria:

    earth_mean_temperature_k : annual T2M in Kelvin
    earth_annual_minimum_k   : coldest monthly T2M_MIN across the year, K
    earth_diurnal_range_k    : mean monthly (T2M_MAX - T2M_MIN), K
    earth_elevation_m        : geometry.coordinates[2], metres above sea level

POWER climatology is a ~0.5-degree monthly climatology derived from
MERRA-2 (and GPM for precip), so matching by nearest cached site is
cheap and good enough; new coordinates far from any cached site return
None (the criteria are then simply skipped).

Example:
    python -m parsers.power --lat -24.08 --lon -69.92
"""

import glob
import json
import math
import os

from parsers.geo import distance_km

DEFAULT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "data", "real", "nasa_power")
MATCH_RADIUS_KM = 150.0  # POWER cells are ~55 km; be generous for coastal sites.
MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
          "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]


def _monthly_values(param):
    """[v for each of the 12 months], ignoring POWER's -999 fill."""
    out = []
    for m in MONTHS:
        v = param.get(m)
        if v is None:
            continue
        if isinstance(v, (int, float)) and v > -900:
            out.append(float(v))
    return out


def _annual(param, monthly):
    ann = param.get("ANN")
    if isinstance(ann, (int, float)) and ann > -900:
        return float(ann)
    return sum(monthly) / len(monthly) if monthly else None


def summarise(doc):
    """One POWER JSON document -> {criterion: value or None}."""
    params = doc.get("properties", {}).get("parameter", {}) or {}
    t2m = params.get("T2M", {}) or {}
    tmax = params.get("T2M_MAX", {}) or {}
    tmin = params.get("T2M_MIN", {}) or {}

    t2m_m = _monthly_values(t2m)
    tmax_m = _monthly_values(tmax)
    tmin_m = _monthly_values(tmin)

    mean_c = _annual(t2m, t2m_m)
    min_c = min(tmin_m) if tmin_m else None
    # Mean diurnal range: average of per-month (max - min) over months with both.
    diurnal_c = None
    if tmax_m and tmin_m:
        pairs = [tmax.get(m, None) for m in MONTHS], [tmin.get(m, None) for m in MONTHS]
        diffs = [a - b for a, b in zip(*pairs)
                 if isinstance(a, (int, float)) and isinstance(b, (int, float))
                 and a > -900 and b > -900]
        if diffs:
            diurnal_c = sum(diffs) / len(diffs)

    geom = doc.get("geometry", {}).get("coordinates", []) or []
    elev = float(geom[2]) if len(geom) >= 3 and isinstance(geom[2], (int, float)) else None

    def to_k(c):
        return None if c is None else c + 273.15

    return {
        "earth_mean_temperature_k": to_k(mean_c),
        "earth_annual_minimum_k": to_k(min_c),
        "earth_diurnal_range_k": diurnal_c,  # a delta, same magnitude in C and K
        "earth_elevation_m": elev,
    }


class Power:
    """Lookup table over cached NASA POWER JSON files."""

    def __init__(self, folder=DEFAULT_DIR):
        if not os.path.isdir(folder):
            raise FileNotFoundError(folder)
        self.folder = folder
        self._entries = []  # [(lat, lon, summary_dict)]
        for path in sorted(glob.glob(os.path.join(folder, "*.json"))):
            try:
                with open(path, encoding="utf-8") as f:
                    doc = json.load(f)
            except (OSError, json.JSONDecodeError):
                continue
            geom = doc.get("geometry", {}).get("coordinates", []) or []
            if len(geom) < 2:
                continue
            lon, lat = float(geom[0]), float(geom[1])
            self._entries.append((lat, lon, summarise(doc)))
        if not self._entries:
            raise FileNotFoundError(f"no POWER JSON files in {folder}")

    def _nearest(self, lat, lon):
        best = None
        best_d = math.inf
        for plat, plon, summary in self._entries:
            d = distance_km(lat, lon, plat, plon, planet="earth")
            if d < best_d:
                best_d = d
                best = summary
        return best, best_d

    def query(self, lat, lon, radius_km=None):  # radius_km unused; kept for API parity
        summary, d = self._nearest(lat, lon)
        if summary is None or d > MATCH_RADIUS_KM:
            return {k: None for k in (
                "earth_mean_temperature_k",
                "earth_annual_minimum_k",
                "earth_diurnal_range_k",
                "earth_elevation_m",
            )}
        return dict(summary)


def main():
    import argparse
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lat", type=float, required=True)
    ap.add_argument("--lon", type=float, required=True)
    ap.add_argument("--folder", default=DEFAULT_DIR)
    args = ap.parse_args()

    power = Power(args.folder)
    print(json.dumps(power.query(args.lat, args.lon), indent=2))


if __name__ == "__main__":
    main()
