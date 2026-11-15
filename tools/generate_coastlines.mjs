// Generates data/earth_coastlines.json (land outlines for the offline Earth globe)
// from Natural Earth 1:110m land polygons.
//
//   npm install --no-save world-atlas@2 topojson-client@3
//   node tools/generate_coastlines.mjs
//
// Output: { source, rings: [[lon, lat, lon, lat, ...], ...] }, coordinates in
// degrees rounded to 0.1°. Rings are cut at the antimeridian (as in Natural
// Earth); the globe skips those artificial edges when stroking coastlines.

import { writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const require = createRequire(join(process.cwd(), "noop.js"));
const topojson = require("topojson-client");
const world = require("world-atlas/land-110m.json");

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const land = topojson.feature(world, world.objects.land);

const r1 = (v) => Math.round(v * 10) / 10;
const rings = [];
for (const f of land.features) {
  const polys = f.geometry.type === "Polygon" ? [f.geometry.coordinates] : f.geometry.coordinates;
  for (const poly of polys) {
    for (const ring of poly) {
      const flat = [];
      let pl = null, pa = null;
      for (const [lon, lat] of ring) {
        const a = r1(lon), b = r1(lat);
        if (a === pl && b === pa) continue;   // drop duplicates after rounding
        flat.push(a, b);
        pl = a; pa = b;
      }
      if (flat.length >= 8) rings.push(flat);
    }
  }
}

const out = { source: "Natural Earth 1:110m land (via world-atlas@2), public domain", rings };
const path = join(ROOT, "data", "earth_coastlines.json");
writeFileSync(path, JSON.stringify(out));
const pts = rings.reduce((n, r) => n + r.length / 2, 0);
console.log(`Wrote ${path}: ${rings.length} rings, ${pts} points, ${(JSON.stringify(out).length / 1024).toFixed(0)} KB`);
