"""GRS chemical composition at any Mars location (Odyssey GRS 5x5 element maps).

Reuses grs_parser.py (label-driven PDS3 .tab reader). Values are wt%, read from
the 5x5 degree cell that contains the point (GRS cells are ~300 km wide, so a
search radius does not apply). Invalid cells -> None; negatives -> 0.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import grs_parser  # noqa: E402

from parsers.geo import DATA_ROOT, lon_360  # noqa: E402

ELEMENTS = ["cl", "fe", "h2o", "k", "si", "th"]
CELL_DEG = 5.0

# data/real/mars_odyssey_grs is the teammate's download; grs_data/ is the earlier copy.
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CANDIDATE_DIRS = [os.path.join(DATA_ROOT, "mars_odyssey_grs"), os.path.join(_ROOT, "grs_data")]


def _cell(lat, lon):
    return (math.floor(lat / CELL_DEG), math.floor(lon_360(lon) / CELL_DEG))


class GRS:
    def __init__(self, folder=None):
        self.folder = folder or next((d for d in CANDIDATE_DIRS if os.path.isdir(d)), None)
        if not self.folder:
            raise FileNotFoundError(f"No GRS folder found in {CANDIDATE_DIRS}")
        self.grids = {}
        for el in ELEMENTS:
            lbl = os.path.join(self.folder, f"{el}_5x5.lbl")
            if not os.path.exists(lbl):
                continue
            grid = grs_parser.to_grid(grs_parser.read_grs(lbl))
            # Snap each cell-centre row onto its 5x5 cell key
            self.grids[el] = {_cell(la, lo): v for (la, lo), v in grid.items()}

    def query(self, lat, lon, radius_km=None):
        """{'grs_<el>': wt% or None} for the cell containing (lat, lon)."""
        key = _cell(lat, lon)
        return {f"grs_{el}": self.grids[el].get(key) if el in self.grids else None for el in ELEMENTS}
