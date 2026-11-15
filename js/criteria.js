// Criteria for similarities (CfS). Order here is the canonical order used by
// the data files, the scoring engine, sliders and charts.
//
// Each criterion carries the scoring rule from the project's Criteria settings
// (see js/scoring.js for the formulas) and the Earth / Mars datasets that
// measure it.

export const CATEGORIES = [
  { id: "rocks",   name: "Rocks and minerals",    color: "#4a8fe7" },
  { id: "terrain", name: "Landforms and terrain", color: "#9db8db" },
  { id: "climate", name: "Climate and radiation", color: "#2f5fa8" },
  { id: "water",   name: "Water, ice and salts",  color: "#d6dde8" },
];

// Scoring rules (labels shown in the method table).
export const RULES = {
  ratio:    { label: "Ratio",       formula: "min ÷ max" },
  logRatio: { label: "Log ratio",   formula: "min ÷ max of log values" },
  gap:      { label: "Gap + scale", formula: "1 ÷ (1 + |Δ| ÷ scale)" },
  fraction: { label: "Fraction",    formula: "1 − |Δ|" },
  match:    { label: "Match",       formula: "1 if same, else 0" },
};

export const CRITERIA = [
  {
    id: "geology",
    name: "Geology and minerals",
    short: "Geology",
    category: "rocks",
    rule: { type: "ratio" },
    measures: ["Basaltic", "Phyllosilicates / clay", "Sulfates", "Carbonates", "Silica / evaporites"],
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
    rule: { type: "ratio" },
    measures: ["Slope", "Local relief", "Roughness", "Relative elevation"],
    earth: ["Copernicus DEM GLO-30", "USGS 3DEP (US)"],
    mars: ["MOLA MEGDR, 128 px/°"],
    note: "Raw elevation is not compared: Mars has no sea level.",
    rationale: "Terrain affects descent and landing, and whether a location is a plausible landing site or base.",
  },
  {
    id: "aeolian",
    name: "Aeolian bedforms",
    short: "Aeolian",
    category: "terrain",
    rule: { type: "ratio" },
    measures: ["Bedform type", "Size and spacing"],
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
    rule: { type: "logRatio" },
    measures: ["Skylight / pit presence", "Tube diameter"],
    earth: ["ASU Lava Tube Database", "Ape Cave LiDAR", "Monte Intraleo LiDAR", "Iceland lava tube minerals"],
    mars: ["USGS MGC3 cave catalog", "HiRISE"],
    note: "Mars lava tubes are 10–100× wider, so diameters are compared on a log scale.",
    rationale: "Caves shelter people and equipment from radiation and temperature extremes.",
  },
  {
    id: "temperature",
    name: "Temperature",
    short: "Temperature",
    category: "climate",
    rule: { type: "gap", scale: 0.1 },
    measures: ["Mean (scale ≈ 10 K)", "Annual minimum (≈ 15 K)", "Diurnal range (≈ 25–30 K)"],
    earth: ["MODIS", "ECOSTRESS", "NASA POWER 2 m air temperature"],
    mars: ["THEMIS", "Mars Climate Sounder (MCS)"],
    note: "Compared in Kelvin at matching local times.",
    rationale: "Temperature affects battery health and material stress, and drives the design of rovers, suits, landers and modules.",
  },
  {
    id: "uv",
    name: "UV radiation",
    short: "UV",
    category: "climate",
    rule: { type: "ratio" },
    measures: ["Surface UV index"],
    earth: ["TROPOMI surface UV"],
    mars: ["Modeled UV (MCS dust opacity, checked against REMS at Gale)"],
    note: "Mars surface UV is modeled, not measured.",
    rationale: "UV damages equipment, so exposed hardware needs UV-resistant materials.",
  },
  {
    id: "aridity",
    name: "Aridity and water availability",
    short: "Aridity",
    category: "climate",
    rule: { type: "ratio" },
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
    rule: { type: "ratio" },
    measures: ["Ice presence", "Depth to ice"],
    earth: ["NSIDC GGD318 permafrost and ground-ice map"],
    mars: ["Odyssey GRS neutron and hydrogen maps", "SHARAD radar"],
    note: "The Earth map covers the Arctic only.",
    rationale: "Buried ice is a source of drinking water, oxygen and fuel for a Mars base.",
  },
  {
    id: "salts",
    name: "Salt deliquescence potential",
    short: "Salts",
    category: "water",
    rule: { type: "fraction" },
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
    rule: { type: "match", threshold: 0.5 },
    measures: ["Patterned ground", "Gullies"],
    earth: ["Permafrost Discovery Gateway ice-wedge polygons"],
    mars: ["Global map of gullied hillslopes (Noblet et al.)", "HiRISE", "CTX"],
    note: "Mars gullies occur only at 26–83°S and 28–76°N.",
    rationale: "Freeze–thaw landforms point to where ground ice is present.",
  },
];

export const CRITERIA_IDS = CRITERIA.map((c) => c.id);

export const categoryOf = (criterion) => CATEGORIES.find((c) => c.id === criterion.category);

// Slider presets (importance 0-1), in CRITERIA order.
export const PRESETS = {
  Balanced:          [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
  "Rover mobility":  [0.4, 1.0, 0.9, 0.1, 0.6, 0.3, 0.2, 0.2, 0.1, 0.3],
  Astrobiology:      [0.9, 0.2, 0.2, 0.6, 0.5, 0.8, 1.0, 0.7, 0.9, 0.6],
  "Habitat / base":  [0.4, 0.7, 0.4, 1.0, 0.9, 0.9, 0.4, 1.0, 0.4, 0.5],
};
