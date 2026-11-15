// Builds snowflake.html: a single self-contained page that renders inside the
// Snowflake (Snowsight / Cowork) HTML sandbox, which enforces a strict CSP and
// has no network access.
//
//   node tools/build_snowflake.mjs
//
// Differences from index.html (the GitHub Pages build):
//   - No jsDelivr / Cesium ion: the CesiumJS globes are replaced by offline
//     canvas globes (js/canvas-globes.js).
//   - Fonts in assets/fonts/ (Noto Sans, and Narwal once added) are inlined.
//   - No location images: js/photos.js is replaced by js/photos-offline.js.
//   - Chart.js loads from the sandbox's vendored /libs/ path.
//   - css/styles.css, every js/ module, every data/ file and the logo are inlined.
//
// Re-run this after changing index.html, css/, js/, data/ or assets/.

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, posix, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "snowflake.html");
const read = (p) => readFileSync(join(ROOT, p), "utf8");

// Modules swapped for the sandbox build.
const SUBSTITUTE = { "js/globes.js": "js/canvas-globes.js", "js/photos.js": "js/photos-offline.js" };
const DATA_FILES = ["data/earth_sites.json", "data/earth_grid.json", "data/mars_regions.json", "data/earth_coastlines.json"];
const LOGO = "assets/ch4-logo.jpg";

// ------------------------------------------------------------- mini bundler
const IMPORT_RE = /import\s*\{([\s\S]*?)\}\s*from\s*["'](.+?)["'];?/g;
const modules = new Map();   // path -> transformed source
const order = [];

function resolveImport(from, spec) {
  const p = posix.normalize(posix.join(posix.dirname(from), spec));
  return SUBSTITUTE[p] || p;
}

function load(path) {
  if (modules.has(path)) return;
  modules.set(path, null);   // cycle guard
  let src = read(path);
  const deps = [];
  src = src.replace(IMPORT_RE, (_, names, spec) => {
    const dep = resolveImport(path, spec);
    deps.push(dep);
    const binds = names.split(",").map((s) => s.trim()).filter(Boolean)
      .map((s) => s.replace(/^(\w+)\s+as\s+(\w+)$/, "$1: $2")).join(", ");
    return `const { ${binds} } = __modules[${JSON.stringify(dep)}];`;
  });
  if (/\bimport\s*\(|^\s*import\s/m.test(src)) throw new Error(`${path}: unsupported import form`);
  const exported = [];
  src = src.replace(/^export\s+((?:async\s+)?function\*?|const|let|class)\s+(\w+)/gm, (_, kind, name) => {
    exported.push(name);
    return `${kind} ${name}`;
  });
  if (/^export\s/m.test(src)) throw new Error(`${path}: unsupported export form`);
  deps.forEach(load);
  modules.set(path, `// ---- ${path}\n__modules[${JSON.stringify(path)}] = (() => {\n${src}\nreturn { ${exported.join(", ")} };\n})();`);
  order.push(path);
}

load("js/app.js");
const bundle = `const __modules = {};\n${order.map((p) => modules.get(p)).join("\n\n")}\n`;

// ---------------------------------------------------------------- page edits
const safeScript = (s) => s.replace(/<\/(script)/gi, "<\\/$1").replace(/<!--/g, "<\\!--");
const safeJSON = (s) => JSON.stringify(JSON.parse(s)).replace(/</g, "\\u003c");

let html = read("index.html");
const replaceOnce = (needle, value) => {
  const n = typeof needle === "string" ? html.split(needle).length - 1 : (html.match(needle) || []).length;
  if (n !== 1) throw new Error(`Expected exactly one match for ${needle}, found ${n}`);
  html = html.replace(needle, () => value);
};

const today = new Date().toISOString().slice(0, 10);
const metadata = {
  generated: today,
  intent: "Mars Analog Finder (CH4, NASA Space Apps): weight similarity criteria, pick a Mars location, rank the most similar Earth locations.",
  dataSources: DATA_FILES.map((path) => ({ type: "file", path })),
  sections: [
    { id: "hero", title: "Find Mars on Earth", producerNotes: "Static intro; stats are filled in from the embedded data at load." },
    { id: "how", title: "Three steps from Mars to Earth", producerNotes: "Static description of the scoring formula in js/scoring.js." },
    { id: "priorities", title: "Set your mission priorities", dataSources: [{ type: "file", path: "js/criteria.js" }], producerNotes: "Criteria and presets come from js/criteria.js." },
    { id: "target", title: "Choose a location on Mars", dataSources: [{ type: "file", path: "data/mars_regions.json" }], producerNotes: "Offline canvas Mars globe (js/canvas-globes.js) with a procedural texture." },
    { id: "results", title: "Your closest Earth analogs", dataSources: [{ type: "file", path: "data/earth_sites.json" }, { type: "file", path: "data/earth_grid.json" }], producerNotes: "Scores computed client-side by js/scoring.js. The bundled data is DEMO placeholder values; rebuild with tools/build_snowflake.mjs after replacing data/." },
  ],
};

replaceOnce('<meta name="viewport" content="width=device-width, initial-scale=1" />',
  `<meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="snowflake-source" content="cortex-agent-authored" />
  <script type="application/json" id="snowflake-report-metadata">
${JSON.stringify(metadata, null, 2).replace(/</g, "\\u003c")}
  </script>`);

// Cesium and CDN scripts are blocked by the sandbox CSP; fonts are inlined below.
replaceOnce(/\s*<link rel="preload" href="assets\/fonts\/[^"]*" as="font"[^>]*\/>/, "");
replaceOnce(/\s*<link rel="stylesheet" href="https:\/\/cdn\.jsdelivr\.net\/npm\/cesium[^"]*" \/>/, "");
replaceOnce(/\s*<script>window\.CESIUM_BASE_URL[^<]*<\/script>/, "");
replaceOnce(/\s*<script src="https:\/\/cdn\.jsdelivr\.net\/npm\/cesium[^"]*" defer><\/script>/, "");
replaceOnce(/<script src="https:\/\/cdn\.jsdelivr\.net\/npm\/chart\.js@4\.4\.4\/dist\/chart\.umd\.js" defer><\/script>/,
  '<script src="/libs/chart.js@4.4.4/chart.umd.js"></script>');

// Fonts referenced by the stylesheet become data: URIs. A font file that does not
// exist yet (Narwal until it is added) is dropped from its src list, so the
// sandbox never sees a request it would block.
const css = read("css/styles.css").replace(/,?\s*url\("\.\.\/(assets\/fonts\/[^"]+)"\)\s*format\("woff2"\)/g, (m, path) => {
  if (!existsSync(join(ROOT, path))) { console.warn(`${path} not found: left out of the build.`); return ""; }
  const lead = m.trimStart().startsWith(",") ? ", " : "";
  return `${lead}url(data:font/woff2;base64,${readFileSync(join(ROOT, path)).toString("base64")}) format("woff2")`;
});
if (/url\("\.\./.test(css)) throw new Error("Unresolved relative url() in styles.css");
replaceOnce('<link rel="stylesheet" href="css/styles.css" />', `<style>\n${css.replace(/<\/style/gi, "<\\/style")}\n  </style>`);

const dataTags = DATA_FILES.map((p) => `<script type="application/json" data-src="${p}">${safeJSON(read(p))}</script>`).join("\n  ");
replaceOnce('<script type="module" src="js/app.js"></script>',
  `${dataTags}\n  <script type="module">\n${safeScript(bundle)}\n  </script>`);

replaceOnce(/Globes powered by <a href="https:\/\/cesium\.com\/platform\/cesium-ion\/"[^>]*>CesiumJS &amp; Cesium ion<\/a>/,
  "Offline build: globes rendered locally on canvas");

// Logo: inline once as a data: URI on the nav logo (the first <img>); a small
// module script (deferred, runs before the app) copies it to the other slots,
// so the image is not embedded 4 times.
// Without the file, drop the tags entirely, since a request the sandbox blocks
// is reported as a render error.
if (existsSync(join(ROOT, LOGO))) {
  const uri = `data:image/jpeg;base64,${readFileSync(join(ROOT, LOGO)).toString("base64")}`;
  let first = true;
  html = html.replace(/(src|href)="assets\/ch4-logo\.jpg"/g, (m, attr) => {
    if (attr === "src" && first) { first = false; return `src="${uri}"`; }
    return "data-logo";
  });
  replaceOnce('  <script type="module">', `  <script type="module">document.querySelectorAll("[data-logo]").forEach((el) => { el[el.tagName === "LINK" ? "href" : "src"] = document.querySelector(".brand-logo").src; });</script>\n  <script type="module">`);
} else {
  console.warn(`${LOGO} not found: building without the logo.`);
  html = html.replace(/\s*<link rel="icon"[^>]*href="assets\/ch4-logo\.jpg"[^>]*>/, "")
    .replace(/<img [^>]*src="assets\/ch4-logo\.jpg"[^>]*>/g, "")
    .replace('<html lang="en">', '<html lang="en" class="no-logo">');
}
if (html.includes(LOGO)) throw new Error("Unresolved logo reference");

// Fail loudly if anything would still reach the network.
const remote = html.match(/(?:src|href)=["']https?:\/\/(?!cesium\.com)[^"']+/g) || [];
const bad = remote.filter((r) => !r.startsWith('href="https://')).concat(/\bfetch\(/.test(html.replace(/const res = await fetch\(path\);/, "")) ? ["fetch()"] : []);
if (bad.length) throw new Error(`Remote resources remain: ${bad.join(", ")}`);
if (/\son[a-z]+\s*=\s*["']/i.test(html.replace(/<script[\s\S]*?<\/script>/gi, ""))) throw new Error("Inline event handler found");
if (/<form[\s>]/i.test(html)) throw new Error("<form> found; sandbox blocks form submission");

writeFileSync(OUT, html);
console.log(`Wrote ${OUT} (${(html.length / 1024).toFixed(0)} KB, modules: ${order.join(", ")})`);
