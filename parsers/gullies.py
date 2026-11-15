"""Mars gullies at any location (Noblet et al., Zenodo 10581763).

Uses the point table GG_Aspect_Gradient_stats.txt
(columns POINTID, LON, LAT, ASPECT, SLOPE, ROI; LON in -180..180, Mars2000).
The table is loaded once into a 1-degree bin index, then each query only
checks nearby bins.

Gullies were only mapped in two latitude bands (about 26-83 S and 28-76 N per
the README). The bands are taken from the actual data extent per hemisphere,
padded by MAPPED_PAD_DEG. Outside them the result is None (not mapped);
inside them a count of 0 means "no gullies".
"""

import math
import os

from parsers.geo import DATA_ROOT, bbox_deg, lon_180, within

DEFAULT_FILE = os.path.join(DATA_ROOT, "mars_gullies_noblet", "GG_Aspect_Gradient_stats.txt")
MAPPED_PAD_DEG = 1.0


class Gullies:
    def __init__(self, path=DEFAULT_FILE):
        import pandas as pd
        self.bins = {}
        cols = {"LON": "float32", "LAT": "float32", "SLOPE": "float32"}
        for chunk in pd.read_csv(path, usecols=list(cols), dtype=cols, chunksize=500_000):
            chunk = chunk.dropna()
            for lon, lat, slope in zip(chunk["LON"].to_numpy(), chunk["LAT"].to_numpy(),
                                       chunk["SLOPE"].to_numpy()):
                key = (math.floor(lat), math.floor(lon_180(float(lon))))
                self.bins.setdefault(key, []).append((float(lat), float(lon), float(slope)))
        self.n_points = sum(len(v) for v in self.bins.values())
        lats = [k[0] for k in self.bins]
        south = [b for b in lats if b < 0]
        north = [b for b in lats if b >= 0]
        self.bands = [(min(h) - MAPPED_PAD_DEG, max(h) + 1 + MAPPED_PAD_DEG) for h in (south, north) if h]

    def _mapped(self, lat):
        return any(lo <= lat <= hi for lo, hi in self.bands)

    def query(self, lat, lon, radius_km=50):
        """Gully presence (1/0), point count and mean slope (deg) within radius_km."""
        if not self._mapped(lat):
            return {"gully_presence": None, "gully_points": None, "gully_mean_slope": None}
        box = bbox_deg(lat, lon, radius_km)
        lo, hi, dlon = box
        lon = lon_180(lon)
        slopes = []
        span = int(math.ceil(dlon)) + 1
        lon_bins = {math.floor(lon_180(lon + k)) for k in range(-span, span + 1)}
        for blat in range(math.floor(lo), math.floor(hi) + 1):
            for blon in lon_bins:
                for plat, plon, s in self.bins.get((blat, blon), ()):
                    if within(lat, lon, plat, plon, radius_km, box):
                        slopes.append(s)
        return {
            "gully_presence": 1 if slopes else 0,
            "gully_points": len(slopes),
            "gully_mean_slope": sum(slopes) / len(slopes) if slopes else None,
        }
