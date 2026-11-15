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
    id: "topography",
    name: "Topography",
    short: "Topography",
    category: "terrain",
    rule: { type: "basic" },
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
    id: "aeolian",
    name: "Aeolian bedforms",
    short: "Aeolian",
    category: "terrain",
    rule: { type: "basic" },
    parts: [
      { name: "Bedform size / spacing", rule: { type: "basic" } },
    ],
    measures: ["Bedform size and spacing"],
    earth: ["Sentinel-2", "Landsat"],
    mars: ["HiRISE", "CTX"],
    note: "Some large Mars ripples have no Earth equivalent.",
    rationale: "Wind-blown sand wears rovers down and reduces the irradiance reaching solar panels.",
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
    // DEMO data is scaled 0-1, so the site uses 0.1 here. With real Kelvin values,
    // use the per-part scales below (10 / 15 / 27.5 K), as analog_scoring.py does.
    rule: { type: "gap", scale: 0.1 },
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
    id: "aridity",
    name: "Aridity and water availability",
    short: "Aridity",
    category: "climate",
    rule: { type: "basicOrFraction" },
    parts: [
      { name: "Aridity (water vapor column)", rule: { type: "basicOrFraction" } },
      { name: "Vegetation (NDVI)", rule: { type: "basic" } },
    ],
    measures: ["Water vapor column", "Vegetation (NDVI)"],
    earth: ["ERA5", "GPM precipitation", "MODIS NDVI"],
    mars: ["Mars Climate Database (MCD)"],
    note: "Mars NDVI is 0, so the barest Earth sites score best.",
    rationale: "Aridity limits where microbes can survive and helps model the Martian climate.",
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
    id: "salts",
    name: "Salt deliquescence potential",
    short: "Salts",
    category: "water",
    rule: { type: "fraction" },
    parts: [
      { name: "Salt deliquescence (fraction of time above threshold)", rule: { type: "fraction" } },
    ],
    measures: ["Chloride", "Perchlorate"],
    earth: ["ERA5 hourly relative humidity and temperature"],
    mars: ["Mars Climate Database (MCD)"],
    note: "Fraction of time above each salt's deliquescence point, compared one salt at a time.",
    rationale: "Perchlorates pull moisture from the air to form liquid brine, one route to surface water on Mars.",
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
// Order: geology, topography, aeolian, caves, temperature, aridity, ice, salts, periglacial
export const PRESETS = {
  Balanced:          [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
  "Rover mobility":  [0.4, 1.0, 0.9, 0.1, 0.6, 0.2, 0.2, 0.1, 0.3],
  Astrobiology:      [0.9, 0.2, 0.2, 0.6, 0.5, 1.0, 0.7, 0.9, 0.6],
  "Habitat / base":  [0.4, 0.7, 0.4, 1.0, 0.9, 0.4, 1.0, 0.4, 0.5],
};
