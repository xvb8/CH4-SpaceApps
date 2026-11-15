"""
Chemical composition similarity module (Mars data: Odyssey GRS).

GRS measures ELEMENTS (not minerals) on coarse 5 x 5 degree cells, so this
module compares element concentrations Mars vs Earth, one element at a time.
Each element is its own independent criterion, scored with the Basic rule.

Flow:
  1. load_grs_grid()      read one element's GRS table (lat, lon, value)
  2. extract_locations()  look up each location's 5x5 cell -> {location: value}
  3. score_elements()     Mars vs Earth per element, every combination
"""

import math

from analog_scoring import basic, combine_results

# The 6 GRS 5x5 unsmoothed files (cl/fe/h2o/k/si/th_5x5.tab + .lbl/.xml).
# Each is its own criterion. Check units in each .lbl (wt% vs ppm, esp. Th).
GRS_ELEMENTS = ["cl", "fe", "h2o", "k", "si", "th"]

CELL_SIZE_DEG = 5.0
NODATA = (-9999, -999, -1)


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def _to_0_360(lon):
    return lon % 360


def load_grs_grid(path, lat_col="lat", lon_col="lon", value_col="value",
                  percent=False, nodata=NODATA, sep=None):
    """
    Read one element's GRS table into {(cell_lat, cell_lon): value}.
    lat/lon may be cell centres or corners; they are snapped to the 5-degree cell.
    percent=True converts wt% to mass fraction (divides by 100).
    """
    import pandas as pd
    df = pd.read_csv(path, sep=sep, engine="python")
    df.columns = [c.strip().lower() for c in df.columns]
    grid = {}
    for lat, lon, val in zip(df[lat_col.lower()], df[lon_col.lower()], df[value_col.lower()]):
        if val is None or (isinstance(val, float) and math.isnan(val)) or val in nodata:
            continue
        val = val / 100 if percent else val
        grid[_cell_key(lat, lon)] = val
    return grid


def _cell_key(lat, lon):
    """Snap a lat/lon to its 5x5 cell (south-west corner, lon in 0-360 E)."""
    cell_lat = math.floor(lat / CELL_SIZE_DEG) * CELL_SIZE_DEG
    cell_lon = math.floor(_to_0_360(lon) / CELL_SIZE_DEG) * CELL_SIZE_DEG
    return (cell_lat, cell_lon)


def load_locations(path):
    """Location list CSV with columns: name, lat, lon. Returns [(name, lat, lon)]."""
    import pandas as pd
    df = pd.read_csv(path)
    df.columns = [c.strip().lower() for c in df.columns]
    return list(zip(df["name"], df["lat"], df["lon"]))


# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------

def extract_locations(grid, locations):
    """
    For each location, read the value of the 5x5 cell it falls in.
    Locations in empty / no-data cells get None (skipped in scoring).
    """
    return {name: grid.get(_cell_key(lat, lon)) for name, lat, lon in locations}


def save_dataset(data, path):
    """Write {location: value} as a 'location,value' CSV (read by analog_scoring.load_dataset)."""
    import csv
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["location", "value"])
        for loc, val in data.items():
            w.writerow([loc, "" if val is None else val])


# ---------------------------------------------------------------------------
# Similarity
# ---------------------------------------------------------------------------

def score_element(mars_data, earth_data):
    """Basic rule for one element across every Mars x Earth combination."""
    return {(m, e): basic(mv, ev)
            for m, mv in mars_data.items()
            for e, ev in earth_data.items()}


def score_elements(mars_by_element, earth_by_element):
    """
    mars_by_element / earth_by_element: {element: {location: value}}.
    Only elements present on BOTH sides are scored; each runs independently.
    Returns {"chemical_composition_<element>": {(mars_loc, earth_loc): score}}.
    """
    unknown = (set(mars_by_element) | set(earth_by_element)) - set(GRS_ELEMENTS)
    if unknown:
        raise KeyError(f"Not a chemical composition criterion: {sorted(unknown)}")
    shared = set(mars_by_element) & set(earth_by_element)
    return {f"chemical_composition_{el}": score_element(mars_by_element[el], earth_by_element[el])
            for el in sorted(shared)}


# ---------------------------------------------------------------------------
# Example with made-up values (replace with real GRS files + location list).
# Earth side is a placeholder until the Earth datasets are chosen.
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mars_locations = [("Jezero Crater", 18.4, 77.5), ("Gale Crater", -5.4, 137.8),
                      ("Polar Site", 87.0, 10.0)]

    # Fake 5x5 GRS grids (cell south-west corner -> mass fraction)
    fake_grids = {
        "fe": {(15.0, 75.0): 0.14, (-10.0, 135.0): 0.16},
        "si": {(15.0, 75.0): 0.20, (-10.0, 135.0): 0.21},
        "cl": {(15.0, 75.0): 0.004, (-10.0, 135.0): 0.006},
    }
    mars_by_element = {el: extract_locations(g, mars_locations) for el, g in fake_grids.items()}

    # Earth placeholder: values per location, same units
    earth_by_element = {
        "fe": {"Iceland Lava Fields": 0.10, "Atacama Desert": 0.04},
        "si": {"Iceland Lava Fields": 0.22, "Atacama Desert": 0.30},
        "cl": {"Iceland Lava Fields": 0.001, "Atacama Desert": 0.02},
    }

    for el, data in mars_by_element.items():
        print(el, data)
    combined = combine_results(score_elements(mars_by_element, earth_by_element))
    for mars_loc, earth_map in combined.items():
        print(f"\n=== {mars_loc} ===")
        for earth_loc, scores in earth_map.items():
            print(f"  {earth_loc}: " + ", ".join(
                f"{c}={s:.2f}" if s is not None else f"{c}=skipped" for c, s in scores.items()))
