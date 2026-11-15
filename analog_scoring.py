"""
Mars-Earth analog similarity scoring.

Each criterion compares one Mars value against one Earth value and returns a
score from 0 to 1 (1 = best match), or None when either value is missing.
Missing scores are skipped, never treated as 0.

Combining / weighting criteria is NOT done here; that happens downstream in
`site_weights.py` (and its JS port in `js/scoring.js`, `js/analog-search.js`).

Scoring rules match `site_weights.rules` / `js/scoring.js` so the per-criterion
scores are identical in every layer:
    basic            smaller / larger; if either <= 0: 1 / (1 + |e - m|)
    basicLog         basic on log10(value + 1)
    gap              1 / (1 + |e - m| / scale)
    fraction         max(0, 1 - |e - m|)
    match            0.5 if both on the same side of PRESENT_AT, else 0
    basicOrFraction  fraction if both are 0-1, else basic
"""

import math

# ---------------------------------------------------------------------------
# Scoring rules
# ---------------------------------------------------------------------------

def _missing(*values):
    return any(v is None or (isinstance(v, float) and math.isnan(v)) for v in values)


def _nums(*values):
    """Values as floats ("1" -> 1.0). None if any is missing or not a number, so it is skipped."""
    out = []
    for v in values:
        if isinstance(v, str):
            try:
                v = float(v.strip())
            except ValueError:
                return None
        if _missing(v) or isinstance(v, bool) or not isinstance(v, (int, float)):
            return None
        out.append(float(v))
    return out


def basic(mars, earth):
    """If either value is 0: 1 / (1 + |gap|). Otherwise: smaller / larger.

    Smaller / larger only works for positive values, so a negative value also
    uses 1 / (1 + |gap|) (keeps the score between 0 and 1).
    """
    v = _nums(mars, earth)
    if v is None:
        return None
    mars, earth = v
    if mars <= 0 or earth <= 0:
        return 1 / (1 + abs(mars - earth))
    return min(mars, earth) / max(mars, earth)


def gap_scale(mars, earth, scale):
    """1 / (1 + |gap| / scale). The scale is the gap that scores 0.5."""
    v = _nums(mars, earth)
    if v is None:
        return None
    mars, earth = v
    return 1 / (1 + abs(mars - earth) / scale)


def fraction(mars, earth):
    """1 - |gap|, for values already between 0 and 1."""
    v = _nums(mars, earth)
    if v is None:
        return None
    mars, earth = v
    return max(0.0, 1 - abs(mars - earth))


# Threshold used by the "match" rule when values are numeric 0-1 presence
# indicators (same as site_weights.PRESENT_AT and PRESENT_AT in js/scoring.js).
PRESENT_AT = 0.5


def match(mars, earth):
    """Categories / yes-no: 0.5 if the same, 0 if not.

    - For strings: case-insensitive equality.
    - For numbers in 0-1 (presence indicators): both on the same side of
      PRESENT_AT counts as the same category (mirrors site_weights.similarity).
    """
    if _missing(mars, earth):
        return None
    mv, ev = _nums(mars, earth) or (None, None)
    if mv is not None and ev is not None:
        return 0.5 if (mv >= PRESENT_AT) == (ev >= PRESENT_AT) else 0.0
    same = str(mars).strip().lower() == str(earth).strip().lower()
    return 0.5 if same else 0.0


def basic_log(mars, earth):
    """Basic rule on log10(value + 1). Used for cave tube diameter."""
    v = _nums(mars, earth)
    if v is None or v[0] < 0 or v[1] < 0:  # a negative diameter is invalid -> skipped
        return None
    return basic(math.log10(v[0] + 1), math.log10(v[1] + 1))


def basic_or_fraction(mars, earth):
    """Fraction if both values are between 0 and 1, otherwise Basic."""
    v = _nums(mars, earth)
    if v is None:
        return None
    mars, earth = v
    if 0 <= mars <= 1 and 0 <= earth <= 1:
        return fraction(mars, earth)
    return basic(mars, earth)


# ---------------------------------------------------------------------------
# Ice consistency conversions (apply before scoring)
# ---------------------------------------------------------------------------

# Earth: ESA CCI Permafrost 1 m ground temperature (deg C).
# Mars: Odyssey GRS H2O (upper ~1 m). Note: different quantities - Mars is water
# content, Earth is how far below freezing the ground is.
SCALE_GROUND_TEMP_C = 10  # placeholder: degrees below 0 C that count as fully frozen


def earth_ice_from_ground_temp(temp_c, scale=SCALE_GROUND_TEMP_C):
    """
    ESA CCI 1 m ground temperature (deg C) -> 0 to 1.
    At or above 0 C (thawed) -> 0; colder rises linearly to 1 at -scale C.
    """
    if _missing(temp_c):
        return None
    if temp_c >= 0:
        return 0.0
    return min(1.0, -temp_c / scale)


def mars_ice_from_grs(h2o_value, percent=True, nodata=(-9999, -999)):
    """
    Odyssey GRS hydrogen (H2O-equivalent, 5x5 deg unsmoothed) -> 0 to 1.
    Set percent=False if the file already stores a mass fraction.
    No-data values -> None.
    """
    if _missing(h2o_value) or h2o_value in nodata or h2o_value < 0:
        return None
    value = h2o_value / 100 if percent else h2o_value
    return None if value > 1 else value  # over 100% is not physical -> skipped


# ---------------------------------------------------------------------------
# Criteria settings (22 criteria)
# Each entry: column name -> (group, scoring function)
# Column names must match the imported Mars and Earth tables.
# ---------------------------------------------------------------------------

# Scales are judgment calls; adjust once real results are seen.
SCALE_MEAN_TEMP_K = 10
SCALE_ANNUAL_MIN_K = 15
SCALE_DIURNAL_K = 27.5
SCALE_ELEVATION_M = 1000  # placeholder: gap (m) that scores 0.5; set by the team

CRITERIA = {
    # Rocks and minerals
    "basaltic":              ("Rocks and minerals", basic),
    "phyllosilicates_clay":  ("Rocks and minerals", basic),
    "sulfates":              ("Rocks and minerals", basic),
    "carbonates":            ("Rocks and minerals", basic),
    "silica_evaporites":     ("Rocks and minerals", basic),

    # Landforms and terrain
    "local_relief":          ("Landforms and terrain", basic),
    "roughness":             ("Landforms and terrain", basic),
    # Raw elevation: Mars vs areoid (MOLA), Earth vs sea level. Gap + scale since negatives occur.
    "elevation":             ("Landforms and terrain",
                              lambda m, e: gap_scale(m, e, SCALE_ELEVATION_M)),
    "slope":                 ("Landforms and terrain", basic),
    "bedform_size_spacing":  ("Landforms and terrain", basic),
    "cave_skylight_pit":     ("Landforms and terrain", match),
    "cave_tube_diameter":    ("Landforms and terrain", basic_log),

    # Climate and radiation
    "mean_temperature_k":    ("Climate and radiation",
                              lambda m, e: gap_scale(m, e, SCALE_MEAN_TEMP_K)),
    "annual_minimum_k":      ("Climate and radiation",
                              lambda m, e: gap_scale(m, e, SCALE_ANNUAL_MIN_K)),
    "diurnal_range_k":       ("Climate and radiation",
                              lambda m, e: gap_scale(m, e, SCALE_DIURNAL_K)),
    "aridity":               ("Climate and radiation", basic_or_fraction),  # water vapor column
    "ndvi":                  ("Climate and radiation", basic),

    # Water, ice and salts
    # Mars: Odyssey GRS H2O (mars_ice_from_grs). Earth: ESA CCI 1 m ground temp (earth_ice_from_ground_temp).
    "ice_consistency":       ("Water, ice and salts", fraction),
    # Hourly RH-T: fraction of time above the salt's deliquescence threshold (0-1)
    "salt_deliquescence":    ("Water, ice and salts", fraction),
    # Periglacial landform area per grid cell
    "periglacial_landform_area": ("Water, ice and salts", fraction),  # area fraction 0-1
    "gully_presence":        ("Water, ice and salts", match),
}


# ---------------------------------------------------------------------------
# UI alias map
#
# The JS UI (`js/criteria.js`) rolls several related criteria into one visible
# slider (e.g. "geology" bundles the 5 mineral subcriteria). This map lets
# `score_criterion` be called with either name space and keeps the scoring
# identical across Python and JS.
# ---------------------------------------------------------------------------

UI_ALIASES = {
    # UI id          -> canonical CRITERIA key
    "geology":       "basaltic",            # UI geology = aggregate; scored like basaltic
    "topography":    "local_relief",
    "aeolian":       "bedform_size_spacing",
    "caves":         "cave_tube_diameter",  # log-scale diameter; skylight shown separately
    "temperature":   "mean_temperature_k",
    "ice":           "ice_consistency",
    "salts":         "salt_deliquescence",
    "periglacial":   "periglacial_landform_area",
    # aridity: identical on both sides already
}


def canonical(column):
    """Return the canonical CRITERIA key for either a UI id or a canonical id."""
    return UI_ALIASES.get(column, column)


# ---------------------------------------------------------------------------
# Independent criterion modules
#
# Each criterion runs on its own Mars dataset and its own Earth dataset.
# A dataset is a dict {location: value} for that one criterion, so every
# criterion can be imported and scored on its own, in any order or in parallel.
# ---------------------------------------------------------------------------

def score_criterion(column, mars_data, earth_data):
    """
    Score one criterion for every Mars-Earth pair.
    mars_data / earth_data: {location: value} from that criterion's datasets.
    Returns {(mars_location, earth_location): score}. Missing -> None (skipped).

    Accepts either a canonical CRITERIA key or a UI id (see UI_ALIASES).
    """
    _group, rule = CRITERIA[canonical(column)]
    scores = {}
    for mars_loc, mars_val in mars_data.items():       # hold Mars fixed
        for earth_loc, earth_val in earth_data.items():  # walk down Earth list
            scores[(mars_loc, earth_loc)] = rule(mars_val, earth_val)
    return scores


def run_all(datasets, parallel=True):
    """
    datasets: {column: (mars_data, earth_data)} for whichever criteria have data.
    Criteria with no dataset yet are simply not run.
    Returns {column: {(mars_location, earth_location): score}}.

    Column names may be canonical CRITERIA keys or UI ids (see UI_ALIASES).
    """
    unknown = {c for c in datasets if canonical(c) not in CRITERIA}
    if unknown:
        raise KeyError(f"Not in CRITERIA: {sorted(unknown)}")

    if not parallel:
        return {c: score_criterion(c, m, e) for c, (m, e) in datasets.items()}

    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor() as pool:
        futures = {c: pool.submit(score_criterion, c, m, e) for c, (m, e) in datasets.items()}
        return {c: f.result() for c, f in futures.items()}


def combine_results(criterion_scores):
    """
    Join per-criterion results by location into the final layout:
    {mars_location: {earth_location: {column: score}}}.
    """
    combined = {}
    for column, scores in criterion_scores.items():
        for (mars_loc, earth_loc), score in scores.items():
            combined.setdefault(mars_loc, {}).setdefault(earth_loc, {})[column] = score
    return combined


def load_dataset(path, location_col="location", value_col="value"):
    """Load one criterion's CSV into {location: value}. Blank cells -> None."""
    import pandas as pd
    df = pd.read_csv(path)
    df = df.astype(object).where(df.notna(), None)
    return dict(zip(df[location_col], df[value_col]))


def print_results(combined):
    for mars_loc, earth_map in combined.items():
        print(f"\n=== {mars_loc} ===")
        for earth_loc, scores in earth_map.items():
            parts = [f"{c}={s:.2f}" for c, s in scores.items() if s is not None]
            print(f"  {earth_loc}: " + ", ".join(parts))


# ---------------------------------------------------------------------------
# Example with made-up values. Each criterion has its own separate datasets.
# Replace with load_dataset(...) calls once real data is imported.
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    datasets = {
        # Rocks and minerals (e.g. CRISM vs EMIT)
        "basaltic": ({"Jezero Crater": 0.8},
                     {"Atacama Desert": 0.4, "Iceland Lava Fields": 0.9}),
        # Climate (e.g. THEMIS vs MODIS)
        "mean_temperature_k": ({"Jezero Crater": 210, "Gale Crater": 220},
                               {"Atacama Desert": 290, "Iceland Lava Fields": 275}),
        # Ice consistency: GRS H2O (percent, converted) vs ESA CCI 1 m ground temp (deg C, converted)
        "ice_consistency": ({"Jezero Crater": mars_ice_from_grs(4.5), "Gale Crater": mars_ice_from_grs(-9999)},
                             {"Atacama Desert": None,
                              "Iceland Lava Fields": earth_ice_from_ground_temp(-1.5)}),
        # Periglacial landform area per grid cell
        "periglacial_landform_area": ({"Jezero Crater": 0.12},
                                      {"Atacama Desert": 0.0, "Iceland Lava Fields": 0.15}),
    }

    print_results(combine_results(run_all(datasets)))
