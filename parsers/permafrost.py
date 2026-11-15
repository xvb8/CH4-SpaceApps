"""Earth permafrost coverage (ESA CCI Permafrost L4 PFR, fv05, 2023).

Reads the Pan-Arctic NetCDF-4 file
    data/real/esa_permafrost/ESACCI-PERMAFROST-L4-PFR-MODISLST_CRYOGRID-AREA4_PP-2023-fv05.0.nc

The PFR layer is a 0.01-deg grid of permafrost area fraction in percent
(0-100), covering 25-85 N and all longitudes. Values of 255 are no-data
(ocean or outside the modelled area).

At each Earth location we average the PFR values that fall inside a
radius_km disc (defaults to 50 km), then convert to a 0-1 fraction so it
can be compared directly against the Mars `periglacial_landform_area`
from parsers/gullies.py (also 0-1 per grid cell). Outside the data
footprint (lat < 25 N or only no-data) the value stays None, never 0.

Output columns:
  earth_pfr_percent               the raw window-mean permafrost fraction (0-100)
  earth_periglacial_landform_area the same value as 0-1 (feeds the criterion)
"""

import os

from parsers.geo import DATA_ROOT, PLANET_RADIUS_KM, bbox_deg, distance_km

DEFAULT_FILE = os.path.join(
    DATA_ROOT,
    "esa_permafrost",
    "ESACCI-PERMAFROST-L4-PFR-MODISLST_CRYOGRID-AREA4_PP-2023-fv05.0.nc",
)

NODATA = 255


class Permafrost:
    def __init__(self, path=DEFAULT_FILE):
        if not os.path.exists(path):
            raise FileNotFoundError(path)
        self.path = path
        # Load small coord vectors once; keep the big PFR array lazy so we
        # only pay for the windows we actually sample.
        import h5py
        import numpy as np
        self._np = np
        self._h5 = h5py
        self._file = h5py.File(path, "r")
        self.lat = self._file["lat"][:].astype(np.float64)     # 6000 values, 85 -> 25 (descending) or 25 -> 85
        self.lon = self._file["lon"][:].astype(np.float64)     # 36000 values, -180 -> 180
        self._pfr = self._file["PFR"]                           # shape (1, 6000, 36000) uint8
        self._lat_desc = self.lat[0] > self.lat[-1]
        self.north = float(self.lat.max())
        self.south = float(self.lat.min())
        self._dlat = abs(float(self.lat[1] - self.lat[0]))
        self._dlon = abs(float(self.lon[1] - self.lon[0]))

    def close(self):
        self._file.close()

    def _lat_slice(self, lo, hi):
        """Return a (start, stop) slice into self.lat that covers [lo, hi]."""
        np = self._np
        if self._lat_desc:
            i0 = int(np.searchsorted(-self.lat, -hi))
            i1 = int(np.searchsorted(-self.lat, -lo, side="right"))
        else:
            i0 = int(np.searchsorted(self.lat, lo))
            i1 = int(np.searchsorted(self.lat, hi, side="right"))
        return max(0, i0), min(len(self.lat), i1)

    def _lon_slice(self, lo, hi):
        np = self._np
        j0 = int(np.searchsorted(self.lon, lo))
        j1 = int(np.searchsorted(self.lon, hi, side="right"))
        return max(0, j0), min(len(self.lon), j1)

    def mean_fraction(self, lat, lon, radius_km=50.0):
        """Window-mean PFR (percent). Returns None outside the footprint or when the window is all no-data."""
        if lat < self.south - self._dlat or lat > self.north + self._dlat:
            return None
        np = self._np
        lo_lat, hi_lat, dlon = bbox_deg(lat, lon, radius_km, planet="earth")
        i0, i1 = self._lat_slice(lo_lat, hi_lat)
        if i0 >= i1:
            return None
        # Longitude box may wrap the antimeridian; split into two reads.
        slices = []
        lo_lon, hi_lon = lon - dlon, lon + dlon
        if lo_lon >= -180 and hi_lon <= 180:
            slices.append(self._lon_slice(lo_lon, hi_lon))
        else:
            if lo_lon < -180:
                slices.append(self._lon_slice(lo_lon + 360, 180))
                slices.append(self._lon_slice(-180, hi_lon))
            else:
                slices.append(self._lon_slice(lo_lon, 180))
                slices.append(self._lon_slice(-180, hi_lon - 360))
        total, count = 0.0, 0
        lat_window = self.lat[i0:i1]
        for j0, j1 in slices:
            if j0 >= j1:
                continue
            block = self._pfr[0, i0:i1, j0:j1]  # uint8 (nrows, ncols)
            if block.size == 0:
                continue
            lon_window = self.lon[j0:j1]
            # Build a mask of cells inside the geodesic disc.
            llat, llon = np.meshgrid(lat_window, lon_window, indexing="ij")
            dlat_rad = np.radians(llat - lat)
            mean_lat = np.radians((llat + lat) / 2)
            dlon_rad = np.radians(((llon - lon + 180) % 360) - 180)
            d_km = PLANET_RADIUS_KM["earth"] * np.sqrt(dlat_rad ** 2 + (np.cos(mean_lat) * dlon_rad) ** 2)
            good = (block != NODATA) & (d_km <= radius_km)
            if not good.any():
                continue
            vals = block[good].astype(np.float64)
            total += float(vals.sum())
            count += int(good.sum())
        if count == 0:
            return None
        return total / count

    def query(self, lat, lon, radius_km=50.0):
        pct = self.mean_fraction(lat, lon, radius_km)
        return {
            "earth_pfr_percent": pct,
            "earth_periglacial_landform_area": None if pct is None else pct / 100.0,
        }


def _cli():
    import argparse
    import json
    ap = argparse.ArgumentParser(description="Sample ESA CCI permafrost PFR at a point.")
    ap.add_argument("--lat", type=float, required=True)
    ap.add_argument("--lon", type=float, required=True)
    ap.add_argument("--radius", type=float, default=50.0)
    ap.add_argument("--file", default=DEFAULT_FILE)
    args = ap.parse_args()
    pf = Permafrost(args.file)
    try:
        print(json.dumps(pf.query(args.lat, args.lon, args.radius), indent=2, default=str))
    finally:
        pf.close()


if __name__ == "__main__":
    _cli()
