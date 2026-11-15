"""Mars gullies at any location (Noblet et al., Zenodo 10581763).

Uses the point table GG_Aspect_Gradient_stats.txt
(columns POINTID, LON, LAT, ASPECT, SLOPE, ROI; LON in -180..180, Mars2000).
Also counts mapped gullied hillslopes (centroids from GlobalGullies_ANoblet.dbf).
The table is loaded once into a 1-degree bin index, then each query only
checks nearby bins.

Gullies were only mapped between 26-83 S and 28-76 N (datasources.md: "compare
only within those latitudes"), so MAPPED_BANDS uses exactly those. Outside them
the result is None (not mapped); inside them a count of 0 means "no gullies".

periglacial_landform_area: gullied-hillslope area (polygons in
GlobalGullies_ANoblet.shp) whose centre lies within radius_km, divided by the
search-circle area, so 0-1. This is the "periglacial landform area per grid cell"
named in datasources.md.
"""

import math
import os

from parsers.geo import DATA_ROOT, bbox_deg, lon_180, within

DEFAULT_FILE = os.path.join(DATA_ROOT, "mars_gullies_noblet", "GG_Aspect_Gradient_stats.txt")
SITES_FILE = os.path.join(DATA_ROOT, "mars_gullies_noblet", "GlobalGullies_ANoblet.dbf")
SHAPES_FILE = os.path.join(DATA_ROOT, "mars_gullies_noblet", "GlobalGullies_ANoblet.shp")
MAPPED_BANDS = [(-83.0, -26.0), (28.0, 76.0)]
MARS_RADIUS_KM = 3389.5


def _ring_area_km2(xs, ys, radius_km=MARS_RADIUS_KM):
    """Signed spherical area of one ring (lon/lat in degrees)."""
    total = 0.0
    for i in range(len(xs) - 1):
        total += math.radians(xs[i + 1] - xs[i]) * (2 + math.sin(math.radians(ys[i])) + math.sin(math.radians(ys[i + 1])))
    return total * radius_km ** 2 / 2


def read_polygon_areas(shp_path):
    """[(centre_lat, centre_lon, area_km2)] for each polygon in a (PolygonZ) shapefile.

    Holes are rings of opposite orientation, so summing signed ring areas removes them.
    """
    import struct
    out = []
    with open(shp_path, "rb") as f:
        f.seek(100)
        while True:
            head = f.read(8)
            if len(head) < 8:
                break
            length = struct.unpack(">i", head[4:8])[0] * 2
            rec = f.read(length)
            if struct.unpack("<i", rec[:4])[0] not in (5, 15, 25):
                continue
            xmin, ymin, xmax, ymax = struct.unpack("<4d", rec[4:36])
            n_parts, n_pts = struct.unpack("<2i", rec[36:44])
            parts = list(struct.unpack(f"<{n_parts}i", rec[44:44 + 4 * n_parts])) + [n_pts]
            base = 44 + 4 * n_parts
            pts = struct.unpack(f"<{2 * n_pts}d", rec[base:base + 16 * n_pts])
            area = 0.0
            for a, b in zip(parts[:-1], parts[1:]):
                area += _ring_area_km2(pts[2 * a:2 * b:2], pts[2 * a + 1:2 * b:2])
            out.append(((ymin + ymax) / 2, (xmin + xmax) / 2, abs(area)))
    return out


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


def circular_mean_deg(angles):
    """Mean compass direction (0 = north, clockwise), so 359 and 1 average to 0."""
    if not angles:
        return None
    x = sum(math.sin(math.radians(a)) for a in angles)
    y = sum(math.cos(math.radians(a)) for a in angles)
    return math.degrees(math.atan2(x, y)) % 360


def pole_facing_fraction(angles, lat, half_width=45.0):
    """Share of slopes facing the nearer pole (within half_width deg of N in the north, S in the south)."""
    if not angles:
        return None
    pole = 0.0 if lat >= 0 else 180.0
    near = sum(1 for a in angles if abs((a - pole + 180) % 360 - 180) <= half_width)
    return near / len(angles)


class Gullies:
    def __init__(self, path=DEFAULT_FILE, sites_path=SITES_FILE, shapes_path=SHAPES_FILE):
        import pandas as pd
        self.bins = {}
        cols = {"LON": "float32", "LAT": "float32", "SLOPE": "float32", "ASPECT": "float32"}
        for chunk in pd.read_csv(path, usecols=list(cols), dtype=cols, chunksize=500_000):
            chunk = chunk.dropna()
            for lon, lat, slope, aspect in zip(chunk["LON"].to_numpy(), chunk["LAT"].to_numpy(),
                                               chunk["SLOPE"].to_numpy(), chunk["ASPECT"].to_numpy()):
                key = (math.floor(lat), math.floor(lon_180(float(lon))))
                self.bins.setdefault(key, []).append((float(lat), float(lon), float(slope), float(aspect)))
        self.n_points = sum(len(v) for v in self.bins.values())
        self.bands = MAPPED_BANDS
        self.sites = {}
        if os.path.exists(sites_path):
            for slat, slon in read_site_centroids(sites_path):
                key = (math.floor(slat), math.floor(lon_180(slon)))
                self.sites.setdefault(key, []).append((slat, lon_180(slon)))

        self.shapes = {}
        if os.path.exists(shapes_path):
            for clat, clon, area in read_polygon_areas(shapes_path):
                key = (math.floor(clat), math.floor(lon_180(clon)))
                self.shapes.setdefault(key, []).append((clat, lon_180(clon), area))

    def _mapped(self, lat):
        return any(lo <= lat <= hi for lo, hi in self.bands)

    def query(self, lat, lon, radius_km=50):
        """Gully presence (1/0), point count and mean slope (deg) within radius_km."""
        if not self._mapped(lat):
            return {"gully_presence": None, "gully_points": None, "gully_mean_slope": None,
                    "gully_mean_aspect": None, "gully_pole_facing": None, "gully_sites": None,
                    "gully_area_km2": None, "periglacial_landform_area": None}
        box = bbox_deg(lat, lon, radius_km)
        lo, hi, dlon = box
        lon = lon_180(lon)
        slopes, aspects = [], []
        span = int(math.ceil(dlon)) + 1
        lon_bins = {math.floor(lon_180(lon + k)) for k in range(-span, span + 1)}
        for blat in range(math.floor(lo), math.floor(hi) + 1):
            for blon in lon_bins:
                for plat, plon, s, a in self.bins.get((blat, blon), ()):
                    if within(lat, lon, plat, plon, radius_km, box):
                        slopes.append(s)
                        aspects.append(a)
        n_sites = 0
        for blat in range(math.floor(lo), math.floor(hi) + 1):
            for blon in lon_bins:
                for slat, slon in self.sites.get((blat, blon), ()):
                    if within(lat, lon, slat, slon, radius_km, box):
                        n_sites += 1
        area = 0.0
        for blat in range(math.floor(lo), math.floor(hi) + 1):
            for blon in lon_bins:
                for clat, clon, a in self.shapes.get((blat, blon), ()):
                    if within(lat, lon, clat, clon, radius_km, box):
                        area += a
        circle = math.pi * radius_km ** 2
        return {
            "gully_area_km2": area if self.shapes else None,
            "periglacial_landform_area": min(1.0, area / circle) if self.shapes and circle > 0 else None,
            "gully_sites": n_sites if self.sites else None,
            "gully_presence": 1 if slopes else 0,
            "gully_points": len(slopes),
            "gully_mean_slope": sum(slopes) / len(slopes) if slopes else None,
            "gully_mean_aspect": circular_mean_deg(aspects),
            "gully_pole_facing": pole_facing_fraction(aspects, lat),
        }
