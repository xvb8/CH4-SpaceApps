// Generates the DEMO data files in /data. All criterion values are made-up
// placeholders (0-1 "normalized indices"); site names and coordinates are real.
//
//   npm install --no-save world-atlas@2 topojson-client@3
//   node tools/generate_demo_data.mjs
//
// Value order everywhere: geology, topography, aeolian, caves, temperature,
// aridity, ice, salts, periglacial  (see js/criteria.js)

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const require = createRequire(import.meta.url);
const topojson = require("topojson-client");
const world = JSON.parse(readFileSync(require.resolve("world-atlas/land-110m.json"), "utf8"));

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const IDS = ["geology", "topography", "aeolian", "caves", "temperature", "aridity", "ice", "salts", "periglacial"];
const toValues = (arr) => Object.fromEntries(IDS.map((id, i) => [id, arr[i]]));

// ---------------------------------------------------------------- Earth sites
const EARTH_SITES = [
  ["atacama", "Yungay, Atacama Desert", "Chile", -24.08, -69.92,
    "The driest non-polar desert on Earth. Hyper-arid soils, nitrate and perchlorate salts and extreme UV make it a classic analog for Martian soil chemistry and life detection.",
    [0.72, 0.62, 0.55, 0.12, 0.58, 0.98, 0.08, 0.86, 0.10]],
  ["dryvalleys", "Wright Valley, McMurdo Dry Valleys", "Antarctica", -77.52, 161.85,
    "Ice-free polar desert with katabatic winds, sublimating ground ice, polygonal terrain and briny ponds. One of the closest climate analogs to Mars.",
    [0.55, 0.70, 0.62, 0.10, 0.95, 0.94, 0.90, 0.80, 0.92]],
  ["donjuan", "Don Juan Pond", "Antarctica", -77.56, 161.19,
    "A calcium-chloride brine pond that stays liquid down to about −50 °C. Water tracks feeding it are a model for deliquescence-driven brines on Mars.",
    [0.48, 0.55, 0.30, 0.05, 0.96, 0.90, 0.78, 0.99, 0.70]],
  ["haughton", "Haughton Crater, Devon Island", "Canada", 75.38, -89.68,
    "A 23 km impact crater in a polar desert. Home of the NASA Haughton-Mars Project for testing rovers, suits and field operations.",
    [0.66, 0.74, 0.30, 0.08, 0.86, 0.80, 0.80, 0.42, 0.88]],
  ["riotinto", "Río Tinto", "Spain", 37.72, -6.55,
    "Acidic, iron-rich river with jarosite and other sulfates that mirror the sulfate deposits seen at Meridiani Planum.",
    [0.93, 0.48, 0.12, 0.20, 0.38, 0.40, 0.02, 0.55, 0.05]],
  ["maunakea", "Mauna Kea summit", "USA (Hawaiʻi)", 19.82, -155.47,
    "High-altitude basaltic volcano with palagonitic, Mars-like regolith, strong UV and thin air. Used for in-situ resource utilization (ISRU) and rover tests.",
    [0.85, 0.80, 0.25, 0.55, 0.52, 0.66, 0.20, 0.20, 0.32]],
  ["kau", "Kaʻū Desert, Kīlauea", "USA (Hawaiʻi)", 19.37, -155.33,
    "Basaltic tephra plains, fresh lava flows and skylit lava tubes. A strong analog for volcanic terrain and caves on Mars.",
    [0.88, 0.58, 0.40, 0.82, 0.35, 0.60, 0.02, 0.22, 0.05]],
  ["holuhraun", "Holuhraun lava field", "Iceland", 64.85, -16.83,
    "One of the youngest flood basalts on Earth, with glacial outwash and black basaltic sand dunes, much like Martian volcanic plains.",
    [0.86, 0.60, 0.58, 0.45, 0.72, 0.55, 0.55, 0.18, 0.66]],
  ["bockfjord", "Bockfjord Volcanic Complex, Svalbard", "Norway", 79.43, 13.32,
    "Arctic volcanic center with carbonate globules similar to those in Martian meteorite ALH84001. Used as an AMASE test site.",
    [0.84, 0.66, 0.20, 0.18, 0.88, 0.70, 0.85, 0.30, 0.86]],
  ["mdrs", "Mars Desert Research Station, Hanksville", "USA (Utah)", 38.41, -110.79,
    "Red Jurassic mudstones, clays and gypsum near the Mars Society habitat used for long-duration crew simulations.",
    [0.80, 0.72, 0.60, 0.15, 0.55, 0.82, 0.05, 0.50, 0.12]],
  ["kelso", "Kelso Dunes, Mojave Desert", "USA (California)", 34.90, -115.70,
    "Tall booming sand dunes and desert pavement. Used to test rover traction and dune morphology.",
    [0.55, 0.55, 0.95, 0.10, 0.60, 0.88, 0.02, 0.40, 0.05]],
  ["badwater", "Badwater Basin, Death Valley", "USA (California)", 36.23, -116.77,
    "Salt pans, evaporites and extreme heat below sea level, with Mars Hill and ancient lake beds nearby.",
    [0.70, 0.30, 0.55, 0.10, 0.45, 0.94, 0.01, 0.82, 0.08]],
  ["sossusvlei", "Sossusvlei, Namib Desert", "Namibia", -24.73, 15.29,
    "Giant star and linear dunes with fog-fed moisture, comparable to the large Martian dune fields.",
    [0.42, 0.50, 0.99, 0.05, 0.50, 0.92, 0.00, 0.48, 0.02]],
  ["timanfaya", "Timanfaya, Lanzarote", "Spain", 29.02, -13.75,
    "Barren basaltic lava fields, cinder cones and lava tubes. Used by the ESA PANGAEA geology training course.",
    [0.87, 0.62, 0.35, 0.78, 0.42, 0.75, 0.00, 0.28, 0.02]],
  ["pilbara", "Dresser Formation, Pilbara", "Australia", -21.15, 119.42,
    "3.5 billion-year-old stromatolites and hydrothermal silica: a reference for searching ancient Martian rocks for biosignatures.",
    [0.90, 0.52, 0.30, 0.12, 0.40, 0.80, 0.00, 0.36, 0.02]],
  ["lonar", "Lonar Crater", "India", 19.98, 76.51,
    "A young impact crater in Deccan basalt with a saline, alkaline lake. A rare basalt-hosted impact analog.",
    [0.86, 0.70, 0.10, 0.10, 0.30, 0.45, 0.00, 0.62, 0.02]],
  ["dallol", "Dallol, Danakil Depression", "Ethiopia", 14.24, 40.30,
    "Hyper-acidic, hypersaline hydrothermal field with sulfur, iron oxides and potash salts. An extreme habitability test bed.",
    [0.92, 0.35, 0.20, 0.08, 0.20, 0.85, 0.00, 0.95, 0.00]],
  ["qaidam", "Dalangtan Playa, Qaidam Basin", "China", 38.50, 92.00,
    "High, cold, hyper-arid playa with chlorides, sulfates and wind-carved yardangs, very similar to Martian evaporite basins.",
    [0.82, 0.78, 0.80, 0.05, 0.70, 0.93, 0.10, 0.88, 0.25]],
  ["lavabeds", "Lava Beds National Monument", "USA (California)", 41.71, -121.51,
    "More than 700 lava tube caves with ice deposits and skylights. Used for cave robotics and subsurface life detection.",
    [0.80, 0.65, 0.12, 0.97, 0.55, 0.55, 0.35, 0.12, 0.20]],
  ["cratersmoon", "Craters of the Moon", "USA (Idaho)", 43.42, -113.52,
    "Basaltic fissure eruptions, spatter cones and lava tubes. Used in NASA's FINESSE and BASALT field campaigns.",
    [0.90, 0.68, 0.30, 0.88, 0.62, 0.70, 0.20, 0.15, 0.30]],
  ["losthammer", "Lost Hammer Spring, Axel Heiberg Island", "Canada", 79.07, -90.35,
    "Perennial sub-zero hypersaline spring flowing through permafrost, an analog for brines and methane seeps on Mars.",
    [0.70, 0.66, 0.10, 0.08, 0.96, 0.72, 0.92, 0.85, 0.82]],
  ["uyuni", "Salar de Uyuni", "Bolivia", -20.13, -67.49,
    "The world's largest salt flat, at 3,650 m. Evaporite crusts, high UV and polygonal salt ridges.",
    [0.76, 0.85, 0.15, 0.02, 0.62, 0.80, 0.05, 0.92, 0.35]],
  ["whitesands", "White Sands", "USA (New Mexico)", 32.88, -106.33,
    "Gypsum dune field, the largest on Earth, analogous to the sulfate-rich dunes around the Martian north pole.",
    [0.78, 0.55, 0.96, 0.02, 0.52, 0.80, 0.02, 0.62, 0.05]],
  ["tolbachik", "Tolbachik volcano, Kamchatka", "Russia", 55.83, 160.33,
    "Active basaltic volcano with fumarolic minerals, lava tubes and snowfields. A cold volcanic analog.",
    [0.88, 0.72, 0.30, 0.65, 0.78, 0.40, 0.60, 0.25, 0.62]],
  ["wadirum", "Wadi Rum", "Jordan", 29.58, 35.42,
    "Red sandstone desert used as a Mars film set and for Austrian Space Forum (ÖWF) AMADEE analog missions.",
    [0.62, 0.70, 0.82, 0.15, 0.48, 0.90, 0.00, 0.35, 0.02]],
  ["lut", "Dasht-e Lut yardangs", "Iran", 30.50, 59.00,
    "Among the hottest surfaces on Earth, with giant wind-sculpted yardangs like those of the Medusae Fossae Formation.",
    [0.66, 0.60, 0.92, 0.05, 0.30, 0.97, 0.00, 0.58, 0.00]],
  ["teide", "Las Cañadas del Teide, Tenerife", "Spain", 28.27, -16.64,
    "High volcanic caldera used to test ExoMars instruments, with basaltic and phonolitic lavas and clear, high-UV skies.",
    [0.84, 0.82, 0.25, 0.45, 0.50, 0.70, 0.05, 0.20, 0.10]],
  ["pinacate", "Pinacate Peaks", "Mexico", 31.77, -113.50,
    "Maar craters, cinder cones and lava fields bordering the Gran Desierto dune sea. Apollo astronauts trained here.",
    [0.84, 0.60, 0.80, 0.40, 0.45, 0.88, 0.00, 0.30, 0.02]],
  ["ergchebbi", "Erg Chebbi, Sahara", "Morocco", 31.15, -3.97,
    "Star dunes beside hamada plains and evaporites. Used for ESA and Mars rover field testing.",
    [0.55, 0.62, 0.97, 0.05, 0.42, 0.95, 0.00, 0.45, 0.00]],
  ["utqiagvik", "Utqiaġvik polygon tundra", "USA (Alaska)", 71.29, -156.79,
    "Ice-wedge polygons on continuous permafrost that closely resemble the patterned ground at the Phoenix landing site.",
    [0.35, 0.40, 0.15, 0.02, 0.85, 0.45, 0.97, 0.35, 0.97]],
];

// ---------------------------------------------------------------- Mars regions
const MARS_REGIONS = [
  ["Jezero Crater", 18.38, 77.58, "Ancient delta and lake basin explored by Perseverance. Carbonates and clays.",
    [0.84, 0.48, 0.55, 0.10, 0.70, 0.92, 0.22, 0.45, 0.20]],
  ["Gale Crater", -5.40, 137.80, "Mount Sharp layered sediments explored by Curiosity, with clays, sulfates and active dunes.",
    [0.80, 0.62, 0.78, 0.12, 0.62, 0.90, 0.15, 0.50, 0.15]],
  ["Meridiani Planum", -1.95, -5.50, "Hematite blueberries and jarosite sulfates explored by Opportunity.",
    [0.88, 0.40, 0.65, 0.05, 0.60, 0.94, 0.08, 0.60, 0.05]],
  ["Utopia Planitia", 46.70, 117.50, "Vast northern plain with scalloped terrain and buried ice.",
    [0.50, 0.30, 0.35, 0.10, 0.85, 0.85, 0.85, 0.55, 0.80]],
  ["Hellas Planitia", -42.40, 70.50, "Deepest impact basin. Higher pressure, gullies and debris-covered glaciers.",
    [0.55, 0.15, 0.40, 0.08, 0.82, 0.80, 0.70, 0.70, 0.72]],
  ["Arsia Mons", -8.26, -120.10, "Tharsis shield volcano with lava tubes and cave skylights on its flanks.",
    [0.88, 0.98, 0.30, 0.95, 0.80, 0.95, 0.20, 0.25, 0.15]],
  ["Olympus Mons", 18.65, -133.80, "The tallest volcano in the Solar System, with basaltic flows and aureole deposits.",
    [0.90, 1.00, 0.25, 0.60, 0.82, 0.96, 0.10, 0.20, 0.08]],
  ["Candor Chasma", -6.50, -71.00, "Valles Marineris trough with thick layered sulfate deposits.",
    [0.92, 0.20, 0.45, 0.30, 0.65, 0.90, 0.12, 0.62, 0.20]],
  ["Mawrth Vallis", 22.60, -16.50, "Some of the richest phyllosilicate (clay) layers on Mars.",
    [0.95, 0.50, 0.40, 0.05, 0.68, 0.90, 0.15, 0.40, 0.10]],
  ["Nili Fossae", 22.00, 75.00, "Carbonate- and olivine-rich troughs near Syrtis Major.",
    [0.93, 0.55, 0.35, 0.10, 0.70, 0.92, 0.20, 0.40, 0.15]],
  ["Gusev Crater", -14.60, 175.40, "Columbia Hills hydrothermal silica found by Spirit.",
    [0.86, 0.50, 0.55, 0.08, 0.65, 0.94, 0.10, 0.48, 0.08]],
  ["Arcadia Planitia", 47.20, -175.80, "Shallow, near-surface ice sheets. A candidate site for crewed landings.",
    [0.48, 0.35, 0.30, 0.05, 0.86, 0.82, 0.92, 0.50, 0.85]],
  ["Phoenix landing site", 68.22, -125.70, "Polygonal ground with excavated water ice and perchlorate salts.",
    [0.45, 0.32, 0.20, 0.02, 0.95, 0.80, 0.98, 0.92, 0.98]],
  ["Terra Sirenum chlorides", -32.00, -165.00, "Ancient highlands with widespread chloride salt deposits.",
    [0.75, 0.70, 0.30, 0.05, 0.75, 0.95, 0.30, 0.95, 0.40]],
  ["Russell Crater megadune", -54.30, 12.90, "A giant dune with seasonal frost-driven gullies.",
    [0.50, 0.55, 0.98, 0.02, 0.88, 0.88, 0.60, 0.50, 0.88]],
  ["Olympia Undae", 81.00, -170.00, "Circumpolar gypsum-rich dune sea.",
    [0.80, 0.30, 0.99, 0.02, 0.96, 0.85, 0.85, 0.65, 0.75]],
  ["Syrtis Major", 8.40, 69.50, "Dark basaltic volcanic plateau.",
    [0.92, 0.60, 0.50, 0.25, 0.70, 0.93, 0.12, 0.30, 0.08]],
  ["Planum Australe", -84.00, 160.00, "South polar layered deposits with a CO₂ and water ice cap.",
    [0.30, 0.65, 0.40, 0.02, 1.00, 0.75, 1.00, 0.55, 0.92]],
  ["Elysium Mons", 25.00, 147.00, "Volcanic province with young lava flows and collapse pits.",
    [0.88, 0.85, 0.25, 0.70, 0.80, 0.94, 0.30, 0.25, 0.25]],
];

// ---------------------------------------------------------------- Earth grid
// Deterministic smooth noise so the 3D score maps look natural.
function hash(x, y, z) {
  let h = (x * 374761393 + y * 668265263 + z * 2147483647) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
}
function valueNoise3(x, y, z, seed) {
  const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
  const xf = x - xi, yf = y - yi, zf = z - zi;
  const s = (t) => t * t * (3 - 2 * t);
  const u = s(xf), v = s(yf), w = s(zf);
  const n = (dx, dy, dz) => hash(xi + dx + seed * 31, yi + dy, zi + dz);
  const lerp = (a, b, t) => a + (b - a) * t;
  return lerp(
    lerp(lerp(n(0, 0, 0), n(1, 0, 0), u), lerp(n(0, 1, 0), n(1, 1, 0), u), v),
    lerp(lerp(n(0, 0, 1), n(1, 0, 1), u), lerp(n(0, 1, 1), n(1, 1, 1), u), v),
    w,
  );
}
function fbm(lat, lon, seed, freq = 2.2) {
  const la = (lat * Math.PI) / 180, lo = (lon * Math.PI) / 180;
  const x = Math.cos(la) * Math.cos(lo), y = Math.cos(la) * Math.sin(lo), z = Math.sin(la);
  let a = 0.5, f = freq, total = 0, norm = 0;
  for (let o = 0; o < 4; o++) {
    total += a * valueNoise3(x * f + 10, y * f + 10, z * f + 10, seed + o);
    norm += a; a *= 0.5; f *= 2;
  }
  return total / norm;
}
const clamp01 = (x) => Math.max(0, Math.min(1, x));
const gauss = (x, mu, sd) => Math.exp(-(((x - mu) / sd) ** 2));
const smooth = (e0, e1, x) => { const t = clamp01((x - e0) / (e1 - e0)); return t * t * (3 - 2 * t); };
const r2 = (x) => Math.round(clamp01(x) * 100) / 100;

function gridValues(lat, lon) {
  const a = Math.abs(lat);
  const desert = gauss(a, 25, 9);          // subtropical desert belts
  const polar = smooth(55, 78, a);
  const n = (s, f) => fbm(lat, lon, s, f);
  const relief = n(3, 3.0);
  const volcanic = smooth(0.58, 0.8, n(5, 3.5));
  return [
    0.30 + 0.35 * desert * n(1) + 0.30 * volcanic + 0.10 * n(2, 5),            // geology
    0.15 + 0.80 * relief ** 1.4,                                                // topography
    0.08 + 0.85 * desert * smooth(0.35, 0.7, n(7, 2.5)),                        // aeolian
    0.02 + 0.85 * volcanic ** 1.6,                                              // caves
    0.20 + 0.70 * polar + 0.15 * desert + 0.10 * relief,                        // temperature (harshness)
    0.10 + 0.75 * desert * (0.6 + 0.4 * n(9)) + 0.35 * polar,                   // aridity
    0.02 + 0.92 * polar * (0.7 + 0.3 * n(11)) + 0.15 * relief * smooth(40, 60, a), // ice
    0.05 + 0.65 * desert * n(13, 3) + 0.20 * polar,                             // salts
    0.03 + 0.90 * polar * (0.6 + 0.4 * n(15, 4)),                               // periglacial
  ].map(r2);
}

// Point-in-polygon on the land MultiPolygon.
const land = topojson.feature(world, world.objects.land);
const polys = land.features.flatMap((f) =>
  f.geometry.type === "Polygon" ? [f.geometry.coordinates] : f.geometry.coordinates,
);
function inRing(ring, x, y) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i], [xj, yj] = ring[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
const isLand = (lon, lat) => polys.some((p) => inRing(p[0], lon, lat) && !p.slice(1).some((h) => inRing(h, lon, lat)));

const STEP = 2.5;
const points = [];
for (let lat = -88.75; lat < 90; lat += STEP) {
  // Thin out longitudes toward the poles so bars stay evenly spaced on the globe.
  const lonStep = Math.min(30, STEP / Math.max(0.2, Math.cos((lat * Math.PI) / 180)));
  for (let lon = -180 + lonStep / 2; lon < 180; lon += lonStep) {
    if (lat < -80) continue; // keep the interior of Antarctica sparse
    if (isLand(lon, lat)) points.push([+lat.toFixed(2), +lon.toFixed(2), ...gridValues(lat, lon)]);
  }
}

// ---------------------------------------------------------------- write
mkdirSync(join(ROOT, "data"), { recursive: true });
const note = "DEMO DATA - criterion values are fabricated placeholders (0-1). Replace with real data.";

writeFileSync(join(ROOT, "data/earth_sites.json"), JSON.stringify({
  note, criteria: IDS,
  sites: EARTH_SITES.map(([id, name, country, lat, lon, description, v]) => ({ id, name, country, lat, lon, description, values: toValues(v) })),
}, null, 1));

writeFileSync(join(ROOT, "data/mars_regions.json"), JSON.stringify({
  note, criteria: IDS,
  regions: MARS_REGIONS.map(([name, lat, lon, description, v]) => ({ name, lat, lon, description, values: toValues(v) })),
}, null, 1));

writeFileSync(join(ROOT, "data/earth_grid.json"), JSON.stringify({
  note, step_deg: STEP, columns: ["lat", "lon", ...IDS], points,
}));

console.log(`earth_sites: ${EARTH_SITES.length}, mars_regions: ${MARS_REGIONS.length}, grid points: ${points.length}`);
