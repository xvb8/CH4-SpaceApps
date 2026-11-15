"""Map parser outputs to the criterion names used by the scoring code.

analog_scoring.CRITERIA names (and the datasources.md source behind each):
  elevation                  <- mola_elevation_m       (MOLA MEGDR topography; megt tiles only)
  cave_skylight_pit          <- cave_skylight_pit      (MGC3)
  cave_tube_diameter         <- cave_max_diameter_m    (MGC3 APC diameter, m)
  mean_temperature_k         <- mcs_surface_temp_k_mean (MCS DDR)
  annual_minimum_k           <- mcs_surface_temp_k_min  (MCS DDR; needs a full year of files)
  diurnal_range_k            <- max - min               (MCS DDR; needs day + night files)
  ice_consistency            <- mars_ice_from_grs(grs_h2o)  (Odyssey GRS, upper ~1 m)
  periglacial_landform_area  <- periglacial_landform_area (Noblet gully polygons, 0-1)
  gully_presence             <- gully_presence         (Noblet gully points)
chemical_composition.score_elements names:
  chemical_composition_<el>  <- to_scoring_units(el, grs_<el>)  (Odyssey GRS, Th in ppm)

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


def to_criteria(row):
    """Raw parser row -> {criterion name: value}; only criteria with a value are kept."""
    out = {c: row.get(src) for c, src in DIRECT.items()}
    tmax, tmin = row.get("mcs_surface_temp_k_max"), row.get("mcs_surface_temp_k_min")
    out["diurnal_range_k"] = tmax - tmin if tmax is not None and tmin is not None else None
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
