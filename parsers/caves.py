"""Mars cave candidates at any location (USGS Mars Global Cave Candidate Catalog, MGC3).

Uses miscellaneous/Mars_Cave_Catalog_shapefile.csv, whose header is correct:
longitude (0-360 E), latitude, Label, TypeCode, Priority, APC_Diameter,
APC_Depth, Comment, Feature. (data/Mars_Cave_Catalog.csv has its header
shifted by one column, so it is not used.)

The catalog is global, so 0 candidates within the radius means "none found".
Diameters are in metres; blank or non-numeric diameters are ignored.
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
            for row in reader:
                lat, lon = _num(row[i_lat]), _num(row[i_lon])
                if lat is None or lon is None:
                    continue
                self.points.append((lat, lon, _num(row[i_dia]), row[i_type].strip()))

    def query(self, lat, lon, radius_km=50):
        """Skylight/pit presence (1/0), candidate count, max and mean diameter (m) within radius_km."""
        box = bbox_deg(lat, lon, radius_km)
        hits = [p for p in self.points if within(lat, lon, p[0], p[1], radius_km, box)]
        dias = [p[2] for p in hits if p[2] is not None and p[2] > 0]
        return {
            "cave_skylight_pit": 1 if hits else 0,
            "cave_candidates": len(hits),
            "cave_max_diameter_m": max(dias) if dias else None,
            "cave_mean_diameter_m": sum(dias) / len(dias) if dias else None,
        }
