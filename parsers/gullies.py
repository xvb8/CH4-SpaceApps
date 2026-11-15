"""Mars gullies at any location (Noblet et al., Zenodo 10581763).

Uses the point table GG_Aspect_Gradient_stats.txt
(columns POINTID, LON, LAT, ASPECT, SLOPE, ROI; LON in -180..180, Mars2000).
Also counts mapped gullied hillslopes (centroids from GlobalGullies_ANoblet.dbf).
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
SITES_FILE = os.path.join(DATA_ROOT, "mars_gullies_noblet", "GlobalGullies_ANoblet.dbf")
MAPPED_PAD_DEG = 1.0


def read_site_centroids(dbf_path):
    """(lat, lon) of each mapped gullied hillslope from the shapefile's .dbf (Centr_Lat, Centr_Long)."""
    import struct
    out = []
    with open(dbf_path, "rb") as f:
        n, header_len, rec_len = struct.unpack("<IHH", f.read(12)[4:12])
        f.seek(32)
        fields, offset = {}, 1  # byte 0 of each record is the deletion flag
        while True:
            d = f.read(32)
            if d[0] == 0x0D:
                break
            name = d[:11].split(b"\0")[0].decode()
            fields[name] = (offset, d[16])
            offset += d[16]
        f.seek(header_len)
        (la_o, la_n), (lo_o, lo_n) = fields["Centr_Lat"], fields["Centr_Long"]
        for _ in range(n):
            r = f.read(rec_len)
            if len(r) < rec_len or r[0:1] == b"*":
                continue
            try:
                out.append((float(r[la_o:la_o + la_n]), float(r[lo_o:lo_o + lo_n])))
            except ValueError:
                continue
    return out


class Gullies:
    def __init__(self, path=DEFAULT_FILE, sites_path=SITES_FILE):
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
        self.sites = {}
        if os.path.exists(sites_path):
            for slat, slon in read_site_centroids(sites_path):
                key = (math.floor(slat), math.floor(lon_180(slon)))
                self.sites.setdefault(key, []).append((slat, lon_180(slon)))

    def _mapped(self, lat):
        return any(lo <= lat <= hi for lo, hi in self.bands)

    def query(self, lat, lon, radius_km=50):
        """Gully presence (1/0), point count and mean slope (deg) within radius_km."""
        if not self._mapped(lat):
            return {"gully_presence": None, "gully_points": None, "gully_mean_slope": None,
                    "gully_sites": None}
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
        n_sites = 0
        for blat in range(math.floor(lo), math.floor(hi) + 1):
            for blon in lon_bins:
                for slat, slon in self.sites.get((blat, blon), ()):
                    if within(lat, lon, slat, slon, radius_km, box):
                        n_sites += 1
        return {
            "gully_sites": n_sites if self.sites else None,
            "gully_presence": 1 if slopes else 0,
            "gully_points": len(slopes),
            "gully_mean_slope": sum(slopes) / len(slopes) if slopes else None,
        }
