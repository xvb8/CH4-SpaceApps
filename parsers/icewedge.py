"""Earth ice-wedge polygon coverage (Permafrost Discovery Gateway, DOI 10.18739/A2KW57K57).

The folder given has the dataset's metadata (EML XML), not the polygons themselves
(those are served as web tiles). From the XML this reads the coverage box
(Pan-Arctic, 66.5-90 N, all longitudes) and the polygon attribute list
(Area, CentroidX, CentroidY, Class, ...), so an Earth location can be checked:

  icewedge_mapped  1 inside the mapped area, 0 outside
  periglacial_landform_area  None everywhere for now (polygons not in the files);
                             outside the mapped area it must stay None, not 0.
"""

import os
import re

from parsers.geo import DATA_ROOT, lon_180

DEFAULT_FILE = os.path.join(DATA_ROOT, "earth_pdg_icewedge",
                            "Ice_wedge_polygon_detection_in_satellite_imagery.xml")


def _first(tag, text):
    m = re.search(r"<%s>\s*([^<]+?)\s*</%s>" % (tag, tag), text)
    return m.group(1) if m else None


class IceWedge:
    def __init__(self, path=DEFAULT_FILE):
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        self.title = _first("title", text)
        self.region = _first("geographicDescription", text)
        self.west = float(_first("westBoundingCoordinate", text))
        self.east = float(_first("eastBoundingCoordinate", text))
        self.north = float(_first("northBoundingCoordinate", text))
        self.south = float(_first("southBoundingCoordinate", text))
        self.attributes = list(dict.fromkeys(re.findall(r"<attributeName>\s*([^<]+?)\s*</attributeName>", text)))
        self.has_polygons = False

    def mapped(self, lat, lon):
        lon = lon_180(lon)
        in_lon = self.west <= lon <= self.east if self.west <= self.east else (lon >= self.west or lon <= self.east)
        return self.south <= lat <= self.north and in_lon

    def query(self, lat, lon, radius_km=None):
        return {
            "icewedge_mapped": 1 if self.mapped(lat, lon) else 0,
            "earth_periglacial_landform_area": None,
        }
