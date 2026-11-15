"""Mars cave candidates at any location (USGS Mars Global Cave Candidate Catalog, MGC3).

Uses miscellaneous/Mars_Cave_Catalog_shapefile.csv, whose header is correct:
longitude (0-360 E), latitude, Label, TypeCode, Priority, APC_Diameter,
APC_Depth, Comment, Feature. (data/Mars_Cave_Catalog.csv has its header
shifted by one column, so it is not used.)

The catalog is global, so 0 candidates within the radius means "none found".
Diameters and depths are in metres; blank, zero or non-numeric values are ignored.
Priority is the catalog's Targeting Priority: 1 = highest, 3 = lowest, 0 = already
imaged by HiRISE (not a rank). cave_best_priority is the lowest non-zero value nearby;
cave_hirise_imaged counts the 0s.
cave_types lists the TypeCodes found (sky, srp, APC, pit, ...).
"""

import csv
import os

from parsers.geo import DATA_ROOT, bbox_deg, within

DEFAULT_FILE = os.path.join(DATA_ROOT, "mars_caves_mgc3", "miscellaneous", "Mars_Cave_Catalog_shapefile.csv")


def _num(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


class Caves:
    def __init__(self, path=DEFAULT_FILE):
        self.points = []
        with open(path, newline="", encoding="utf-8", errors="replace") as f:
            reader = csv.reader(f)
            header = [h.split(":")[0].strip().lower() for h in next(reader)]
            i_lon, i_lat = header.index("longitude"), header.index("latitude")
            i_dia, i_type = header.index("apc_diameter"), header.index("typecode")
            i_dep, i_pri = header.index("apc_depth"), header.index("priority")
            for row in reader:
                lat, lon = _num(row[i_lat]), _num(row[i_lon])
                if lat is None or lon is None:
                    continue
                self.points.append((lat, lon, _num(row[i_dia]), row[i_type].strip(),
                                    _num(row[i_dep]), _num(row[i_pri])))

    def query(self, lat, lon, radius_km=50):
        """Skylight/pit presence (1/0), candidate count, max and mean diameter (m) within radius_km."""
        box = bbox_deg(lat, lon, radius_km)
        hits = [p for p in self.points if within(lat, lon, p[0], p[1], radius_km, box)]
        dias = [p[2] for p in hits if p[2] is not None and p[2] > 0]
        deps = [p[4] for p in hits if p[4] is not None and p[4] > 0]
        pris = [p[5] for p in hits if p[5] is not None and p[5] > 0]
        return {
            "cave_skylight_pit": 1 if hits else 0,
            "cave_candidates": len(hits),
            "cave_max_diameter_m": max(dias) if dias else None,
            "cave_mean_diameter_m": sum(dias) / len(dias) if dias else None,
            "cave_max_depth_m": max(deps) if deps else None,
            "cave_mean_depth_m": sum(deps) / len(deps) if deps else None,
            "cave_best_priority": min(pris) if pris else None,
            "cave_hirise_imaged": sum(1 for p in hits if p[5] == 0),
            "cave_types": ",".join(sorted({p[3] for p in hits if p[3]})) or None,
        }


DATA_CSV = os.path.join(DATA_ROOT, "mars_caves_mgc3", "data", "Mars_Cave_Catalog.csv")
# data/Mars_Cave_Catalog.csv names its columns longitude,latitude,Label,... but the
# values are in the order Label,longitude,latitude,... (header shifted by one).
DATA_CSV_COLUMNS = ["label", "longitude", "latitude", "typecode", "priority",
                    "apc_diameter", "apc_depth", "comment"]


def read_data_csv(path=DATA_CSV):
    """data/Mars_Cave_Catalog.csv with the corrected column order -> {label: row dict}."""
    out = {}
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if len(row) >= len(DATA_CSV_COLUMNS) - 1:
                rec = dict(zip(DATA_CSV_COLUMNS, row))
                out[rec["label"]] = rec
    return out


def cross_check(shapefile_csv=DEFAULT_FILE, data_csv=DATA_CSV):
    """Compare both catalog CSVs; returns (n_shapefile, n_data, differences list)."""
    with open(shapefile_csv, newline="", encoding="utf-8", errors="replace") as f:
        reader = csv.reader(f)
        header = [h.split(":")[0].strip().lower() for h in next(reader)]
        a = {r[header.index("label")]: dict(zip(header, r)) for r in reader}
    b = read_data_csv(data_csv)
    diffs = [(k, "missing", None, None) for k in set(a) ^ set(b)]
    for k in set(a) & set(b):
        for col in ("longitude", "latitude", "typecode", "priority", "apc_diameter", "apc_depth"):
            x, y = a[k].get(col, ""), b[k].get(col, "")
            nx, ny = _num(x), _num(y)
            same = abs(nx - ny) < 1e-4 if nx is not None and ny is not None else x.strip() == y.strip()
            if not same:
                diffs.append((k, col, x, y))
    return len(a), len(b), diffs


if __name__ == "__main__":
    n_a, n_b, d = cross_check()
    print(f"shapefile csv {n_a} rows, data csv {n_b} rows, {len(d)} differences")
