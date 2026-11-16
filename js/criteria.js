// Criteria for similarities (CfS). Order here is the canonical order used by
// the data files, the scoring engine, sliders and charts.
//
// Each criterion carries the scoring rule from the project's Criteria settings
// (see js/scoring.js for the formulas) and the Earth / Mars datasets that
// measure it.
//
// `parts` lists the similarity criteria grouped under each one, with the same
// rules as analog_scoring.py / chemical_composition.py (shown in the Method
// table). `rule` is the one rule the site applies to its single value per criterion.

export const CATEGORIES = [
  { id: "rocks",   name: "Rocks and minerals",    color: "#4a8fe7" },
  { id: "terrain", name: "Landforms and terrain", color: "#9db8db" },
  { id: "climate", name: "Climate and radiation", color: "#2f5fa8" },
  { id: "water",   name: "Water, ice and salts",  color: "#d6dde8" },
];

// Scoring rules (labels shown in the method table).
export const RULES = {
  basic:           { label: "Basic",             formula: "smaller ÷ larger; if either is 0 (or negative): 1 ÷ (1 + |Δ|)" },
  basicLog:        { label: "Basic on logs",     formula: "Basic on log10(value + 1)" },
  gap:             { label: "Gap + scale",       formula: "1 ÷ (1 + |Δ| ÷ scale)" },
  fraction:        { label: "Fraction",          formula: "1 − |Δ|, never below 0" },
  match:           { label: "Match",             formula: "0.5 if same, 0 if not" },
  basicOrFraction: { label: "Basic or Fraction", formula: "Fraction if both are 0–1, otherwise Basic" },
};

export const CRITERIA = [
  {
    id: "geology",
    name: "Geology and minerals",
    short: "Geology",
    category: "rocks",
    rule: { type: "basic" },
    parts: [
      { name: "Basaltic", rule: { type: "basic" } },
      { name: "Phyllosilicates / clay", rule: { type: "basic" } },
      { name: "Sulfates", rule: { type: "basic" } },
      { name: "Carbonates", rule: { type: "basic" } },
      { name: "Silica / evaporites", rule: { type: "basic" } },
      { name: "Chemical composition: Cl, Fe, H₂O, K, Si, Th (Th in ppm)", rule: { type: "basic" } },
    ],
    measures: ["Basaltic", "Phyllosilicates / clay", "Sulfates", "Carbonates", "Silica / evaporites", "Chemical composition (Cl, Fe, H₂O, K, Si, Th)"],
    earth: ["ASTER-GED AG100", "EMIT L2B V002"],
    mars: ["CRISM MTRDR", "TES mineral maps", "Odyssey GRS"],
    note: "Carbonates occur in only a few Mars regions, mainly Nili Fossae.",
    rationale: "Mineral chemistry affects how instruments and drills behave and shapes the materials and design of Mars equipment.",
  },
  {
    // Real data: topography value is elevation in meters (data/parsed/*.csv →
    // tools/csv_to_ui_json.mjs). Gap with a 1 km scale matches the
    // per-part rule and gives sensible scores across Earth/Mars elevations.
    id: "topography",
    name: "Topography",
    short: "Topography",
    category: "terrain",
    rule: { type: "gap", scale: 1000, unit: "m" },
    parts: [
      { name: "Local relief", rule: { type: "basic" } },
      { name: "Roughness", rule: { type: "basic" } },
      { name: "Elevation", rule: { type: "gap", scale: 1000, unit: "m" } },
      { name: "Slope", rule: { type: "basic" } },
    ],
    measures: ["Local relief", "Roughness", "Elevation", "Slope"],
    earth: ["Copernicus DEM GLO-30", "USGS 3DEP (US)"],
    mars: ["MOLA MEGDR, 128 px/°"],
    note: "Elevation is compared directly: Mars against the areoid, Earth against sea level.",
    rationale: "Terrain affects descent and landing, and whether a location is a plausible landing site or base.",
  },
  {
    id: "caves",
    name: "Caves",
    short: "Caves",
    category: "terrain",
    rule: { type: "basicLog" },
    parts: [
      { name: "Skylight / pit presence", rule: { type: "match" } },
      { name: "Tube diameter", rule: { type: "basicLog" } },
    ],
    measures: ["Skylight / pit presence", "Tube diameter"],
    earth: ["ASU Lava Tube Database", "Ape Cave LiDAR", "Monte Intraleo LiDAR", "Iceland lava tube minerals"],
    mars: ["USGS MGC3 cave catalog", "HiRISE"],
    note: "Mars lava tubes are 10–100× wider, so diameters are compared on a log scale.",
    rationale: "Caves shelter people and equipment from radiation and temperature extremes.",
    // Earth lava-tube databases cluster around volcanic provinces; Mars MGC3 is concentrated
    // along the Tharsis/Elysium volcanic belt. Boxes are loose envelopes of the catalogs.
    coverage: {
      earth: [
        { latMin: 18, latMax: 23, lonMin: -161, lonMax: -154 },  // Hawaii
        { latMin: 32, latMax: 50, lonMin: -125, lonMax: -108 },  // US Cascades + Idaho/NM lava fields
        { latMin: 63, latMax: 67, lonMin: -25, lonMax: -13 },    // Iceland
        { latMin: 36, latMax: 46, lonMin: 6, lonMax: 16 },       // Italy (Etna, Monte Intraleo)
        { latMin: -1, latMax: 1, lonMin: -92, lonMax: -89 },     // Galapagos
        { latMin: 27, latMax: 30, lonMin: -19, lonMax: -13 },    // Canary Islands
        { latMin: -28, latMax: -26, lonMin: -110, lonMax: -108 },// Easter Island
        { latMin: -5, latMax: 5, lonMin: 34, lonMax: 42 },       // Kenya rift
      ],
      mars: [{ latMin: -30, latMax: 40, lonMin: -180, lonMax: 180 }],
    },
  },
  {
    id: "temperature",
    name: "Temperature",
    short: "Temperature",
    category: "climate",
    // Real data: temperature value is mean_temperature_k in Kelvin (data/parsed/
    // *.csv → tools/csv_to_ui_json.mjs). 10 K is the per-part Mean scale used
    // by analog_scoring.py.
    rule: { type: "gap", scale: 10, unit: "K" },
    parts: [
      { name: "Mean temperature", rule: { type: "gap", scale: 10, unit: "K" } },
      { name: "Annual minimum", rule: { type: "gap", scale: 15, unit: "K" } },
      { name: "Diurnal range", rule: { type: "gap", scale: 27.5, unit: "K" } },
    ],
    measures: ["Mean", "Annual minimum", "Diurnal range"],
    earth: ["MODIS", "ECOSTRESS", "NASA POWER 2 m air temperature"],
    mars: ["THEMIS", "Mars Climate Sounder (MCS)"],
    note: "Compared in Kelvin at matching local times.",
    rationale: "Temperature affects battery health and material stress, and drives the design of rovers, suits, landers and modules.",
  },
  {
    id: "ice",
    name: "Ice and permafrost",
    short: "Ice",
    category: "water",
    rule: { type: "fraction" },
    parts: [
      { name: "Ice consistency", rule: { type: "fraction" } },
    ],
    measures: ["Ice consistency (upper ~1 m)"],
    earth: ["ESA CCI Permafrost, 1 m ground temperature"],
    mars: ["Odyssey GRS neutron and hydrogen maps"],
    note: "Both sides are converted to 0–1 before comparing: Mars from GRS H₂O, Earth from 1 m ground temperature.",
    rationale: "Buried ice is a source of drinking water, oxygen and fuel for a Mars base.",
    // NSIDC GGD318 covers the Northern Hemisphere high-latitude permafrost belt;
    // Mars neutron/radar ice maps are global.
    coverage: { earth: [{ latMin: 50, latMax: 90 }], mars: "global" },
  },
  {
    id: "periglacial",
    name: "Periglacial ground and gullies",
    short: "Periglacial",
    category: "water",
    rule: { type: "fraction" },
    parts: [
      { name: "Periglacial landform area (fraction of cell)", rule: { type: "fraction" } },
      { name: "Gully presence", rule: { type: "match" } },
    ],
    measures: ["Periglacial landform area", "Gully presence"],
    earth: ["Permafrost Discovery Gateway ice-wedge polygons"],
    mars: ["Global map of gullied hillslopes (Noblet et al.)", "HiRISE", "CTX"],
    note: "Mars gullies occur only at 26–83°S and 28–76°N.",
    rationale: "Freeze–thaw landforms point to where ground ice is present.",
    // PDG ice-wedge polygons span the pan-Arctic; Mars gullies: two mid-latitude bands.
    coverage: {
      earth: [{ latMin: 50, latMax: 90 }],
      mars: [{ latMin: 28, latMax: 76 }, { latMin: -83, latMax: -26 }],
    },
  },
];

export const CRITERIA_IDS = CRITERIA.map((c) => c.id);

export const categoryOf = (criterion) => CATEGORIES.find((c) => c.id === criterion.category);

/**
 * Whether a side ("earth" / "mars") of a criterion's dataset actually covers
 * (lat, lon). A criterion with no `coverage` field, or coverage set to
 * "global" / missing for that side, is treated as globally valid. Coverage is
 * given as either the string "global" or a list of lat/lon boxes; longitudes
 * are optional (missing = full 360°) and the box is inclusive on all edges.
 */
export function inCoverage(criterion, side, lat, lon) {
  const cov = criterion.coverage?.[side];
  if (!cov || cov === "global") return true;
  const nlon = ((((lon ?? 0) + 180) % 360) + 360) % 360 - 180;
  return cov.some((b) => {
    if (lat < b.latMin || lat > b.latMax) return false;
    if (b.lonMin == null || b.lonMax == null) return true;
    // Boxes that wrap the antimeridian: lonMin > lonMax.
    return b.lonMin <= b.lonMax
      ? nlon >= b.lonMin && nlon <= b.lonMax
      : nlon >= b.lonMin || nlon <= b.lonMax;
  });
}

// Slider presets (importance 0-1), in CRITERIA order.
// Order: geology, topography, caves, temperature, ice, periglacial
export const PRESETS = {
  Balanced:          [0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
  "Rover mobility":  [0.4, 1.0, 0.1, 0.6, 0.2, 0.3],
  Astrobiology:      [0.9, 0.2, 0.6, 0.5, 0.7, 0.6],
  "Habitat / base":  [0.4, 0.7, 1.0, 0.9, 1.0, 0.5],
};

// Relative cost of scoring one criterion on one full-resolution cell. Used by
// analog-search.js to order criteria cheap-first during staged scoring (so
// expensive datasets only get opened for cells that still have a chance of
// landing in the top-K). Mirrors CRITERION_COST in analog_search.py.
export const CRITERION_COST = {
  geology: 3,
  topography: 1,
  caves: 5,
  temperature: 1,
  ice: 2,
  periglacial: 5,
};

// Hard filters: criterion id -> minimum similarity in [0, 1]. A cell is
// dropped by the search when that criterion is missing or scores below the
// minimum. Empty by default; the UI can override per-mission or per-session.
// Mirrors HARD_FILTERS in analog_search.py.
export const HARD_FILTERS = {};
