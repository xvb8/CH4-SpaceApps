// Convert data/parsed/*.csv (real parsed measurements) into the JSON shapes
// that js/data.js loads for the UI:
//
//   data/earth_sites.json   { criteria, sites:   [{ id, name, country, lat, lon, description, values: { <criterion>: <number|null> } }] }
//   data/mars_regions.json  { criteria, regions: [{ id, name, lat, lon, description, values: { <criterion>: <number|null> } }] }
//
// CSV columns in data/parsed/*_criteria.csv are raw sub-measurements (K, m, wt%, 0-1).
// The UI's 9 criteria (js/criteria.js CRITERIA) need one aggregate per criterion in the
// native units expected by the matching scoring rule (js/criteria.js RULES):
//
//   geology      basic         mean of chemical_composition_{cl,fe,h2o,k,si,th}  (wt%)
//   topography   gap(1000 m)   elevation                                          (meters)
//   aeolian      -             not in CSV → null  (criterion is skipped by scorer)
//   caves        basicLog      cave_tube_diameter if present, else cave_skylight_pit (presence)
//   temperature  gap(10 K)     mean_temperature_k                                 (Kelvin)
//   aridity      -             not in CSV → null
//   ice          fraction      ice_consistency                                    (0–1)
//   salts        -             not in CSV → null
//   periglacial  fraction      periglacial_landform_area                          (0–1)
//
// Site / region metadata (id, country, description) is preserved from the existing
// data/earth_sites.json and data/mars_regions.json so the detail cards keep their copy.
// New rows that don't appear in the current JSON get a synthesized id and empty extras.
//
// Usage:
//   node tools/csv_to_ui_json.mjs
//
// Writes:
//   data/earth_sites.json
//   data/mars_regions.json
// Does NOT touch data/earth_grid.json (no dense-grid CSV yet).

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

// ---- UI criteria order (must match js/criteria.js CRITERIA_IDS) -------------
const CRITERIA_IDS = [
  "geology", "topography", "aeolian", "caves",
  "temperature", "aridity", "ice", "salts", "periglacial",
];

// Chemistry elements that feed `geology`. Thorium is in ppm in the CSV, the
// others in wt%; `basic` is scale-free (smaller/larger ratio) so mixing units
// after averaging is fine for a single aggregate — individual element scoring
// is still available through the CLI (run_scoring.py).
const CHEM_ELEMENTS = ["cl", "fe", "h2o", "k", "si", "th"];

// ---- tiny CSV parser (handles quoted fields with commas) --------------------
function parseCsv(text) {
  const rows = [];
  let row = [], field = "", inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else inQuotes = false;
      } else field += c;
    } else if (c === '"') {
      inQuotes = true;
    } else if (c === ",") {
      row.push(field); field = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field); field = "";
      if (row.length > 1 || row[0] !== "") rows.push(row);
      row = [];
    } else field += c;
  }
  if (field !== "" || row.length) { row.push(field); rows.push(row); }
  if (!rows.length) return [];
  const header = rows[0];
  return rows.slice(1).map((r) => {
    const obj = {};
    header.forEach((h, i) => { obj[h] = r[i] ?? ""; });
    return obj;
  });
}

const num = (v) => {
  if (v === "" || v == null) return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};

const mean = (xs) => {
  const good = xs.filter((x) => x != null && Number.isFinite(x));
  return good.length ? good.reduce((a, b) => a + b, 0) / good.length : null;
};

// ---- aggregation: one row (CSV dict) → UI {criterion: value} ----------------
function rowToValues(row) {
  const chem = mean(CHEM_ELEMENTS.map((e) => num(row[`chemical_composition_${e}`])));
  const tubeDiameter = num(row.cave_tube_diameter);
  const skylight = num(row.cave_skylight_pit);
  // caves: real tube diameter wins (basicLog over meters); otherwise fall back
  // to the 0/1 skylight-pit marker which basicLog(log10(x+1)) still handles.
  const caves = tubeDiameter != null ? tubeDiameter : skylight;
  return {
    geology: chem,
    topography: num(row.elevation),
    aeolian: null,
    caves,
    temperature: num(row.mean_temperature_k),
    aridity: null,
    ice: num(row.ice_consistency),
    salts: null,
    periglacial: num(row.periglacial_landform_area),
  };
}

// ---- slugify fallback for rows with no existing id --------------------------
const slug = (s) => s
  .toLowerCase()
  .normalize("NFKD")
  .replace(/[^\w\s-]/g, "")
  .trim()
  .replace(/\s+/g, "-")
  .replace(/-+/g, "-");

// ---- main -------------------------------------------------------------------
function convertEarth() {
  const csvPath = join(ROOT, "data/parsed/earth_sites_criteria.csv");
  const outPath = join(ROOT, "data/earth_sites.json");
  const rows = parseCsv(readFileSync(csvPath, "utf8"));

  // Preserve metadata (id, country, description) from the existing file,
  // keyed by name so demo re-writes don't lose the copy.
  const prevMeta = new Map();
  if (existsSync(outPath)) {
    try {
      const prev = JSON.parse(readFileSync(outPath, "utf8"));
      for (const s of prev.sites ?? []) prevMeta.set(s.name, s);
    } catch { /* ignore malformed previous file */ }
  }

  const sites = rows.map((r) => {
    const prev = prevMeta.get(r.name) ?? {};
    return {
      id: prev.id ?? slug(r.name),
      name: r.name,
      country: prev.country ?? "",
      lat: num(r.lat),
      lon: num(r.lon),
      description: prev.description ?? "",
      values: rowToValues(r),
    };
  });

  const out = {
    note: "Real parsed data (data/parsed/earth_sites_criteria.csv). Missing criteria are null; the scorer skips them.",
    source: "data/parsed/earth_sites_criteria.csv",
    criteria: CRITERIA_IDS,
    sites,
  };
  writeFileSync(outPath, JSON.stringify(out, null, 1));
  return { count: sites.length, path: outPath };
}

function convertMars() {
  const csvPath = join(ROOT, "data/parsed/mars_regions_criteria.csv");
  const outPath = join(ROOT, "data/mars_regions.json");
  const rows = parseCsv(readFileSync(csvPath, "utf8"));

  const prevMeta = new Map();
  if (existsSync(outPath)) {
    try {
      const prev = JSON.parse(readFileSync(outPath, "utf8"));
      for (const r of prev.regions ?? []) prevMeta.set(r.name, r);
    } catch { /* ignore */ }
  }

  const regions = rows.map((r) => {
    const prev = prevMeta.get(r.name) ?? {};
    return {
      id: prev.id ?? slug(r.name),
      name: r.name,
      lat: num(r.lat),
      lon: num(r.lon),
      description: prev.description ?? "",
      values: rowToValues(r),
    };
  });

  const out = {
    note: "Real parsed data (data/parsed/mars_regions_criteria.csv). Missing criteria are null; the scorer skips them.",
    source: "data/parsed/mars_regions_criteria.csv",
    criteria: CRITERIA_IDS,
    regions,
  };
  writeFileSync(outPath, JSON.stringify(out, null, 1));
  return { count: regions.length, path: outPath };
}

const e = convertEarth();
const m = convertMars();
console.log(`Wrote ${e.count} Earth sites  → ${e.path}`);
console.log(`Wrote ${m.count} Mars regions → ${m.path}`);
console.log("Note: data/earth_grid.json is unchanged (no dense-grid CSV yet).");
