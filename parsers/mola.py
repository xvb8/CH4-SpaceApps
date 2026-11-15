"""MOLA MEGDR tiles at any location (PDS3 .lbl + .img, 128 pixels per degree).

Reads whatever tiles are in data/real/mars_mola_megdr. Each tile's label says what
it holds (IMAGE NAME), its lat/lon box, size and sample type, so the same code
works for every MEGDR product:

  megt  topography (signed 16-bit, metres vs areoid)  -> mola_elevation_m
  megc  observation counts per pixel (unsigned 8-bit) -> mola_obs_count

The tiles currently given are megc (counts), so only mola_obs_count is filled;
elevation stays None until megt tiles are added. Counts are NOT elevation.
Pixels are read one at a time with seek, so a 65 MB tile is never loaded whole.
"""

import glob
import math
import os
import struct

from parsers.geo import DATA_ROOT, lon_360

DEFAULT_FOLDER = os.path.join(DATA_ROOT, "mars_mola_megdr")

PRODUCT_OUTPUT = {
    "COUNTS_PER_BIN": "mola_obs_count",
    "TOPOGRAPHY": "mola_elevation_m",
}


def _num(text):
    return float(text.split("<")[0].strip().strip('"'))


def parse_lbl(path):
    """Flat KEY -> value dict of a MEGDR label (first value wins)."""
    out = {}
    with open(path, errors="replace") as f:
        for line in f:
            if "=" in line:
                k, v = line.split("=", 1)
                out.setdefault(k.strip(), v.strip())
    return out


class Tile:
    def __init__(self, lbl_path):
        lab = parse_lbl(lbl_path)
        self.name = lab.get("NAME", "").strip('"')
        self.output = PRODUCT_OUTPUT.get(self.name)
        self.lines = int(lab["LINES"])
        self.samples = int(lab["LINE_SAMPLES"])
        self.bits = int(lab["SAMPLE_BITS"])
        self.signed = "UNSIGNED" not in lab["SAMPLE_TYPE"]
        self.big_endian = "MSB" in lab["SAMPLE_TYPE"] or ("LSB" not in lab["SAMPLE_TYPE"] and self.bits > 8)
        self.res = _num(lab["MAP_RESOLUTION"])
        self.lat_max, self.lat_min = _num(lab["MAXIMUM_LATITUDE"]), _num(lab["MINIMUM_LATITUDE"])
        self.lon_w, self.lon_e = _num(lab["WESTERNMOST_LONGITUDE"]), _num(lab["EASTERNMOST_LONGITUDE"])
        img = lab.get("^IMAGE", "").strip('"')
        folder = os.path.dirname(lbl_path)
        matches = [p for p in os.listdir(folder) if p.lower() == img.lower()]
        self.img = os.path.join(folder, matches[0]) if matches else None

    def contains(self, lat, lon):
        lon = lon_360(lon)
        return self.lat_min <= lat <= self.lat_max and self.lon_w <= lon < self.lon_e

    def value(self, lat, lon):
        line = min(self.lines - 1, int(math.floor((self.lat_max - lat) * self.res)))
        sample = min(self.samples - 1, int(math.floor((lon_360(lon) - self.lon_w) * self.res)))
        size = self.bits // 8
        fmt = {(1, False): "B", (1, True): "b", (2, False): "H", (2, True): "h"}[(size, self.signed)]
        with open(self.img, "rb") as f:
            f.seek((line * self.samples + sample) * size)
            raw = f.read(size)
        return struct.unpack((">" if self.big_endian else "<") + fmt, raw)[0]


class MOLA:
    def __init__(self, folder=DEFAULT_FOLDER):
        self.tiles = []
        for lbl in sorted(glob.glob(os.path.join(folder, "*.lbl")) + glob.glob(os.path.join(folder, "*.LBL"))):
            t = Tile(lbl)
            if t.output and t.img:
                self.tiles.append(t)
        self.outputs = sorted({t.output for t in self.tiles} | set(PRODUCT_OUTPUT.values()))

    def query(self, lat, lon, radius_km=None):
        """Pixel value at (lat, lon) per product; None where no tile covers the point."""
        out = {k: None for k in self.outputs}
        for t in self.tiles:
            if out[t.output] is None and t.contains(lat, lon):
                out[t.output] = t.value(lat, lon)
        return out
