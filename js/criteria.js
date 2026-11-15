// Criteria for similarities (CfS). Order here is the canonical order used by
// the data files, the scoring engine, sliders and charts.

export const CATEGORIES = [
  { id: "rocks",   name: "Rocks and minerals",    color: "#ff8fb8", icon: "◆" },
  { id: "terrain", name: "Landforms and terrain", color: "#c49bff", icon: "▲" },
  { id: "climate", name: "Climate and radiation", color: "#7cb8ff", icon: "☀" },
  { id: "water",   name: "Water, ice, and salts", color: "#6ff0d6", icon: "❄" },
];

export const CRITERIA = [
  {
    id: "geology",
    name: "Geology and minerals",
    short: "Geology",
    category: "rocks",
    detail: "Chemical composition",
    items: ["Basaltic", "Phyllosilicates / clay", "Sulfates", "Carbonates", "Silica / evaporites"],
    earth: "ASTER, EMIT, Landsat",
    mars: "CRISM, OMEGA",
    rationale:
      "The chemical composition of the minerals can affect instrument (i.e. equipment and drill) behavior and influence the structure, material, and design of our Mars equipment.",
  },
  {
    id: "topography",
    name: "Topography",
    short: "Topography",
    category: "terrain",
    detail: "Elevation and relief",
    items: [],
    earth: "SRTM, Copernicus DEM",
    mars: "MOLA",
    rationale:
      "The topography (elevation) can affect the descent and landing while impacting a location's likelihood to be a plausible Mars landing site (or base).",
  },
  {
    id: "aeolian",
    name: "Aeolian bedforms",
    short: "Aeolian",
    category: "terrain",
    detail: "Dunes, ripples, megaripples",
    items: ["Bedform size", "Bedform spacing"],
    earth: "Sentinel-2 and Landsat dune and ripple maps",
    mars: "HiRISE, CTX",
    rationale:
      "The wind causing sand dunes and ripples may affect the rover on Mars, wearing the rover out while also decreasing the solar panels' solar irradiance.",
  },
  {
    id: "caves",
    name: "Caves",
    short: "Caves",
    category: "terrain",
    detail: "Shielded subsurface environment",
    items: ["Relative cave tube diameter", "Skylight / pit presence"],
    earth: "Lava tube and cave inventories",
    mars: "Skylight and pit catalogs",
    rationale:
      "Subsurface caves on Mars act as a means of shelter for people and equipment from radiation and temperature.",
  },
  {
    id: "temperature",
    name: "Temperature",
    short: "Temperature",
    category: "climate",
    detail: "Mean, diurnal range, annual minimum",
    items: ["Mean", "Diurnal range", "Annual minimum"],
    earth: "MODIS, ECOSTRESS",
    mars: "THEMIS",
    rationale:
      "The temperature may affect battery health in electronics, cause stress on certain materials, and impact the structural design and materials of the rover, space suit, landing equipment, and rocket modules.",
  },
  {
    id: "uv",
    name: "UV radiation",
    short: "UV",
    category: "climate",
    detail: "Surface UV exposure",
    items: [],
    earth: "UV index (OMI / TROPOMI)",
    mars: "Surface UV index",
    rationale:
      "UV radiation may damage equipment and technology, requiring UV resistant materials around all equipment.",
  },
  {
    id: "aridity",
    name: "Aridity and water availability",
    short: "Aridity",
    category: "climate",
    detail: "Biological habitability",
    items: [],
    earth: "Aridity index, GPM precipitation, MODIS NDVI",
    mars: "Water activity and humidity level",
    rationale:
      "Aridity affects where microbes and primitive organisms can survive on Mars. Simulating the appropriate aridity may also help us better understand Mars' climate.",
  },
  {
    id: "ice",
    name: "Ice and permafrost",
    short: "Ice",
    category: "water",
    detail: "Ice consistency",
    items: [],
    earth: "Ice consistency",
    mars: "Ice consistency",
    rationale:
      "Buried ice is a key component for drinking water, oxygen, and fuel, all critically necessary for starting a Mars colony.",
  },
  {
    id: "salts",
    name: "Salt deliquescence potential",
    short: "Salts",
    category: "water",
    detail: "Relative humidity and temperature envelope",
    items: [],
    earth: "ERA5 hourly RH and temperature (fraction of time above each salt's deliquescence point)",
    mars: "Modeled RH–T over chloride and perchlorate deposits",
    rationale:
      "Salts (perchlorates) pull moisture from the air and create liquid brine, which is one of the ways to obtain liquid water on the surface of Mars.",
  },
  {
    id: "periglacial",
    name: "Periglacial patterned ground and gullies",
    short: "Periglacial",
    category: "water",
    detail: "Signs of freezing and thawing ice",
    items: [],
    earth: "Gully detection from high-resolution imagery",
    mars: "HiRISE, CTX",
    rationale:
      "Periglacial patterns on Mars' surface indicate the freezing and thawing of ice, which may help locate the presence and locations of ground ice on Mars.",
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
