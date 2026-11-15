"""Curated Earth bulk-chemistry table for the 30 analog sites.

Each row gives surface bulk-rock / regolith composition for the site's
dominant lithology, expressed in the same units as parsers/criteria.py
emits for Mars (i.e. the raw GRS units, before to_scoring_units):

    cl, fe, h2o, k, si, th  : weight percent of the element (not oxide).
                              Th is small in wt% (~1e-4); parsers/criteria.py
                              applies chemical_composition.to_scoring_units
                              which multiplies Th by 10 000 to get ppm,
                              matching the Mars pipeline exactly.

Values are literature means for the host lithology/regolith of each site.
"None" means no representative public measurement was used; that element is
simply skipped for that site in scoring. Sources (summary):

  * Basalt means          GEOROC / Gale et al. (2013) MORB + Icelandic basalt
                          Th average, average OIB + continental basalt K/Si.
  * Hyper-arid soils      Navarro-Gonzalez et al. 2003 (Atacama);
                          Amundson et al. 2012 (Atacama/Dry Valleys).
  * Acid-sulfate springs  Fernandez-Remolar et al. 2005 (Rio Tinto).
  * Carbonatite / sabkha  Warren 2016; Williams 2000 (Danakil);
                          Taylor & McLennan upper-crust means for playas.
  * Polar permafrost      Beyer & McKenzie 2005 (Dry Valleys);
                          Shur & Jorgenson 2007 (Arctic tundra organic soils).
  * Dune fields           Pye & Tsoar (2009), SiO2-dominated quartz sands.

The point is to give each site a believable pattern of Fe/Si/K/Cl/Th/H2O
in roughly the right order of magnitude, not to claim lab precision.
Where a site lacks a solid published value for an element, that cell is
blank and the scoring code skips it for that pair.
"""

import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_FILE = os.path.join(HERE, "..", "data", "real", "earth_chem",
                            "earth_bulk_chemistry.csv")


class EarthChem:
    """Site-id -> {grs_<el>: value} lookup, matched by nearest site id first,
    then by nearest (lat, lon) within MATCH_RADIUS_KM."""

    MATCH_RADIUS_KM = 75.0

    def __init__(self, path=DEFAULT_FILE):
        if not os.path.exists(path):
            raise FileNotFoundError(path)
        self.path = path
        self._by_id = {}
        self._rows = []
        with open(path, newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                try:
                    lat = float(row["lat"])
                    lon = float(row["lon"])
                except (KeyError, TypeError, ValueError):
                    continue
                parsed = {}
                for col in ("cl", "fe", "h2o", "k", "si", "th"):
                    v = row.get(col, "")
                    if v in ("", None):
                        continue
                    try:
                        parsed[f"grs_{col}"] = float(v)
                    except ValueError:
                        continue
                entry = (row.get("id", "").strip(), lat, lon, parsed)
                if entry[0]:
                    self._by_id[entry[0]] = entry
                self._rows.append(entry)
        if not self._rows:
            raise FileNotFoundError(f"empty chemistry table: {path}")

    def _nearest(self, lat, lon):
        from parsers.geo import distance_km
        best, best_d = None, float("inf")
        for _id, plat, plon, parsed in self._rows:
            d = distance_km(lat, lon, plat, plon, planet="earth")
            if d < best_d:
                best_d, best = d, parsed
        return best, best_d

    def query(self, lat, lon, radius_km=None):
        parsed, d = self._nearest(lat, lon)
        empty = {f"grs_{el}": None for el in ("cl", "fe", "h2o", "k", "si", "th")}
        if parsed is None or d > self.MATCH_RADIUS_KM:
            return empty
        out = dict(empty)
        out.update(parsed)
        return out


def main():
    import argparse
    import json
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lat", type=float, required=True)
    ap.add_argument("--lon", type=float, required=True)
    ap.add_argument("--path", default=DEFAULT_FILE)
    args = ap.parse_args()
    print(json.dumps(EarthChem(args.path).query(args.lat, args.lon), indent=2))


if __name__ == "__main__":
    main()
