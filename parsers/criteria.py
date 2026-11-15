"""Map parser outputs to the criterion names used by the scoring code.

analog_scoring.CRITERIA names (Mars source / Earth source):
  elevation                  mola_elevation_m           / earth_elevation_m          (NASA POWER meta)
  cave_skylight_pit          cave_skylight_pit (MGC3)   / -
  cave_tube_diameter         cave_max_diameter_m (MGC3) / -
  mean_temperature_k         mcs_surface_temp_k_mean    / earth_mean_temperature_k   (NASA POWER T2M)
  annual_minimum_k           mcs_surface_temp_k_min     / earth_annual_minimum_k     (NASA POWER T2M_MIN)
  diurnal_range_k            max - min (MCS DDR)        / earth_diurnal_range_k      (NASA POWER T2M_MAX - T2M_MIN)
  ice_consistency            mars_ice_from_grs(grs_h2o) / -
  periglacial_landform_area  periglacial_landform_area  / earth_periglacial_landform_area (ESA CCI permafrost)
  gully_presence             gully_presence (Noblet)    / -
chemical_composition.score_elements names:
  chemical_composition_<el>  to_scoring_units(el, grs_<el>)  Mars: Odyssey GRS; Earth: curated bulk-chemistry table

Values that are missing stay None, so the criterion is skipped, never scored 0.
Criteria with no data file yet (basaltic, clay, sulfates, carbonates, silica,
local_relief, roughness, slope, bedforms, aridity, NDVI, salt deliquescence)
are simply absent.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from analog_scoring import CRITERIA, mars_ice_from_grs  # noqa: E402
from chemical_composition import GRS_ELEMENTS, to_scoring_units  # noqa: E402

DIRECT = {
    "elevation": "mola_elevation_m",
    "cave_skylight_pit": "cave_skylight_pit",
    "cave_tube_diameter": "cave_max_diameter_m",
    "mean_temperature_k": "mcs_surface_temp_k_mean",
    "annual_minimum_k": "mcs_surface_temp_k_min",
    "periglacial_landform_area": "periglacial_landform_area",
    "gully_presence": "gully_presence",
}

# Earth parsers prefix their columns to avoid clashing with Mars columns on
# the same criterion. These aliases let to_criteria() pick them up on the
# Earth side without the Mars parsers having to rename anything.
EARTH_ALIASES = {
    "periglacial_landform_area": "earth_periglacial_landform_area",
    "mean_temperature_k": "earth_mean_temperature_k",
    "annual_minimum_k": "earth_annual_minimum_k",
    "elevation": "earth_elevation_m",
}


def to_criteria(row):
    """Raw parser row -> {criterion name: value}; only criteria with a value are kept."""
    out = {}
    for c, src in DIRECT.items():
        v = row.get(src)
        if v is None:
            alt = EARTH_ALIASES.get(c)
            if alt is not None:
                v = row.get(alt)
        out[c] = v
    tmax, tmin = row.get("mcs_surface_temp_k_max"), row.get("mcs_surface_temp_k_min")
    if tmax is not None and tmin is not None:
        out["diurnal_range_k"] = tmax - tmin
    else:
        # Earth side ships a precomputed diurnal range from NASA POWER.
        out["diurnal_range_k"] = row.get("earth_diurnal_range_k")
    h2o = row.get("grs_h2o")
    out["ice_consistency"] = mars_ice_from_grs(h2o) if h2o is not None else None
    for el in GRS_ELEMENTS:
        out[f"chemical_composition_{el}"] = to_scoring_units(el, row.get(f"grs_{el}"))
    return {k: v for k, v in out.items() if v is not None}


def scoring_inputs(mars_rows, earth_rows):
    """Build inputs for the scoring code from parsed Mars and Earth rows.

    Returns (datasets, chem):
      datasets: {criterion: ({mars_name: v}, {earth_name: v})} for analog_scoring.run_all
      chem:     ({el: {mars_name: v}}, {el: {earth_name: v}}) for chemical_composition.score_elements
    A criterion is included only if both planets have at least one value.
    """
    def by_criterion(rows):
        out = {}
        for r in rows:
            for k, v in to_criteria(r).items():
                out.setdefault(k, {})[r["name"]] = v
        return out

    m, e = by_criterion(mars_rows), by_criterion(earth_rows)
    datasets = {c: (m[c], e[c]) for c in CRITERIA if c in m and c in e}
    chem_m = {el: m[f"chemical_composition_{el}"] for el in GRS_ELEMENTS if f"chemical_composition_{el}" in m}
    chem_e = {el: e[f"chemical_composition_{el}"] for el in GRS_ELEMENTS if f"chemical_composition_{el}" in e}
    return datasets, (chem_m, chem_e)
