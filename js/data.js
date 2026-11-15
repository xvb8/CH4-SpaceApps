// Loads the analog datasets.
//
// To replace the demo data with a real dataset, keep the same JSON shapes:
//
//   data/earth_sites.json   { sites:   [{ id, name, country, lat, lon, description, values: { <criterion>: 0-1 } }] }
//   data/earth_grid.json    { columns: ["lat","lon", <criteria...>], points: [[lat, lon, v1, v2, ...], ...] }
//   data/mars_regions.json  { regions: [{ name, lat, lon, description, values: { <criterion>: 0-1 } }] }
//
// Criterion ids are listed in js/criteria.js. Values are normalized indices in [0, 1]
// that are directly comparable between Earth and Mars.

import { CRITERIA_IDS } from "./criteria.js";

async function getJSON(path) {
  // Self-contained builds (tools/build_snowflake.mjs) embed each file as
  // <script type="application/json" data-src="<path>"> so no network is needed.
  const embedded = document.querySelector(`script[type="application/json"][data-src="${path}"]`);
  if (embedded) return JSON.parse(embedded.textContent);
  const res = await fetch(path);
  if (!res.ok) throw new Error(`Failed to load ${path} (${res.status})`);
  return res.json();
}

export async function loadData() {
  const [sitesFile, gridFile, marsFile, coastFile] = await Promise.all([
    getJSON("data/earth_sites.json"),
    getJSON("data/earth_grid.json"),
    getJSON("data/mars_regions.json"),
    // Optional: land outlines for the offline Earth globe (tools/generate_coastlines.mjs).
    getJSON("data/earth_coastlines.json").catch(() => null),
  ]);

  const sites = sitesFile.sites.map((s) => ({ ...s, kind: "site" }));

  const col = Object.fromEntries(gridFile.columns.map((c, i) => [c, i]));
  const grid = gridFile.points.map((p, i) => ({
    id: `grid-${i}`,
    kind: "grid",
    name: `Grid cell ${p[col.lat].toFixed(1)}°, ${p[col.lon].toFixed(1)}°`,
    lat: p[col.lat],
    lon: p[col.lon],
    values: Object.fromEntries(CRITERIA_IDS.map((k) => [k, p[col[k]]])),
  }));

  return {
    sites,
    grid,
    marsRegions: marsFile.regions,
    coastlines: coastFile ? coastFile.rings : null,
    isDemo: Boolean(sitesFile.note && sitesFile.note.startsWith("DEMO")),
    gridStep: gridFile.step_deg ?? 2.5,
  };
}
