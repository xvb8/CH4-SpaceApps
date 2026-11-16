"""Mars Climate Sounder (MCS) DDR temperature at any location.

Built from the DDR label given (2025070100_DDR.LBL, MRO-M-MCS-5-DDR-V6.2):
  ^TABLE = (<name>.TAB, <start byte>), ASCII, ROWS, ROW_BYTES,
  ^STRUCTURE = MCS_DDR1.FMT for the per-profile columns (lat, lon, surface T, ...).

Column positions come from MCS_DDR1.FMT (OBJECT = COLUMN with NAME / START_BYTE /
BYTES), not hard-coded, so this works for any DDR version. Until the .TAB and the
.FMT files are in the folder, query() returns None for every output (skipped).

Outputs per location (profiles whose lat/lon fall within radius_km):
  mcs_surface_temp_k_mean, mcs_surface_temp_k_min, mcs_surface_temp_k_max, mcs_profiles
These feed mean_temperature_k / annual_minimum_k / diurnal_range_k once
enough files (seasons, local times) are present.
"""

import glob
import os
import re

from parsers.geo import DATA_ROOT, bbox_deg, within

DEFAULT_FOLDER = os.path.join(DATA_ROOT, "pds_mcs")
# Column names to look for in MCS_DDR1.FMT (first match wins, case-insensitive)
LAT_NAMES = ("PROFILE_LAT",)
LON_NAMES = ("PROFILE_LON",)
TSURF_NAMES = ("T_SURF",)
NODATA_AT_OR_BELOW = -9999.0
OUTPUTS = ("mcs_surface_temp_k_mean", "mcs_surface_temp_k_min", "mcs_surface_temp_k_max", "mcs_profiles")


def _find(folder, name):
    hits = [p for p in os.listdir(folder) if p.lower() == name.lower()]
    return os.path.join(folder, hits[0]) if hits else None


def parse_label(path):
    """TABLE pointer, start byte, rows, row bytes and structure file of a DDR label."""
    text = open(path, errors="replace").read()
    m = re.search(r'\^TABLE\s*=\s*\(\s*"([^"]+)"\s*,\s*(\d+)', text)
    get = lambda key: (re.search(r"\b%s\s*=\s*(\S+)" % key, text) or [None, None])[1]
    struct = re.search(r'\^STRUCTURE\s*=\s*"([^"]+)"', text)
    return {
        "table": m.group(1) if m else None,
        "start_byte": int(m.group(2)) if m else 1,
        "rows": int(get("ROWS")) if get("ROWS") else None,
        "row_bytes": int(get("ROW_BYTES")) if get("ROW_BYTES") else None,
        "structure": struct.group(1) if struct else "MCS_DDR1.FMT",
    }


def parse_fmt(path):
    """{COLUMN NAME: (start_byte 1-based, bytes)} from a PDS3 .FMT file."""
    cols, cur = {}, {}
    for line in open(path, errors="replace"):
        line = line.strip()
        if line.startswith("OBJECT") and "COLUMN" in line:
            cur = {}
        elif line.startswith("END_OBJECT"):  # checked before "=": "END_OBJECT = COLUMN"
            if cur.get("NAME") and "START_BYTE" in cur and "BYTES" in cur:
                cols[cur["NAME"].upper()] = (int(cur["START_BYTE"]), int(cur["BYTES"]))
            cur = {}
        elif "=" in line:
            k, v = [x.strip() for x in line.split("=", 1)]
            cur[k] = v.strip('"')
    return cols


def _pick(cols, names):
    for n in names:
        if n in cols:
            return cols[n]
    return None


def _field(line, pos):
    start, size = pos
    try:
        v = float(line[start - 1:start - 1 + size].strip().strip('"'))
    except ValueError:
        return None
    return None if v <= NODATA_AT_OR_BELOW else v


class MCS:
    def __init__(self, folder=DEFAULT_FOLDER, extra_folders=()):
        self.profiles = []  # (lat, lon, t_surf_k)
        self.missing = []
        folders = [f for f in (folder, *extra_folders) if f and os.path.isdir(f)]
        # DDR archives sometimes nest the .LBL/.TAB inside a subdirectory whose
        # name mirrors the .TAB file (e.g. data/real/pds_mcs/2006092416_DDR.TAB/...),
        # so walk each root recursively rather than globbing a single level.
        labels = []
        for f in folders:
            labels += glob.glob(os.path.join(f, "**", "*DDR*.LBL*"), recursive=True)
            labels += glob.glob(os.path.join(f, "**", "*ddr*.lbl"), recursive=True)
        for lbl in sorted(set(labels)):
            self._load(lbl)

    def _load(self, lbl):
        folder = os.path.dirname(lbl)
        lab = parse_label(lbl)
        tab = _find(folder, lab["table"]) if lab["table"] else None
        fmt = _find(folder, lab["structure"])
        if not tab or not fmt:
            self.missing.append((os.path.basename(lbl), [n for n, p in ((lab["table"], tab), (lab["structure"], fmt)) if not p]))
            return
        cols = parse_fmt(fmt)
        lat_c, lon_c, t_c = _pick(cols, LAT_NAMES), _pick(cols, LON_NAMES), _pick(cols, TSURF_NAMES)
        if not (lat_c and lon_c and t_c):
            self.missing.append((os.path.basename(lbl), ["lat/lon/T_surf columns in " + lab["structure"]]))
            return
        with open(tab, errors="replace") as f:
            f.read(lab["start_byte"] - 1)  # skip the header before the table
            for line in f:
                lat, lon, t = _field(line, lat_c), _field(line, lon_c), _field(line, t_c)
                if lat is not None and lon is not None and t is not None:
                    self.profiles.append((lat, lon, t))

    def query(self, lat, lon, radius_km=200):
        if not self.profiles:
            return {k: None for k in OUTPUTS}
        box = bbox_deg(lat, lon, radius_km)
        ts = [t for plat, plon, t in self.profiles if within(lat, lon, plat, plon, radius_km, box)]
        if not ts:
            return {k: None for k in OUTPUTS}
        return {
            "mcs_surface_temp_k_mean": sum(ts) / len(ts),
            "mcs_surface_temp_k_min": min(ts),
            "mcs_surface_temp_k_max": max(ts),
            "mcs_profiles": len(ts),
        }
