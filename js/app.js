import { CRITERIA, CATEGORIES, CRITERIA_IDS, PRESETS, RULES, categoryOf } from "./criteria.js";
import { loadData } from "./data.js";
import { marsProfileAt, scoreLocations, topN, angularDistance } from "./scoring.js";
import { startStarfield } from "./background.js";
import { cesiumAvailable, initIon, createMarsViewer, createEarthViewer } from "./globes.js";
import {
  setupChartDefaults, drawGrouped, drawMetric, drawWeights, drawScatter, drawProfile, metricLabel, TOP_COLORS,
} from "./charts.js";

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

const state = {
  data: null,
  importance: [...PRESETS.Balanced],
  target: null,        // { lat, lon, profile, neighbors }
  result: null,        // { scored, means, spread, weights, top, sites }
  selectedId: null,
  layer: "total",
  mode: "bars",        // Earth map style: "bars" or "color"
  mars: null,
  earth: null,
  earthPromise: null,
};

// ------------------------------------------------------------------ helpers
function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
const fmtLat = (lat) => `${Math.abs(lat).toFixed(2)}° ${lat >= 0 ? "N" : "S"}`;
const fmtLon = (lon) => `${Math.abs(lon).toFixed(2)}° ${lon >= 0 ? "E" : "W"}`;
const fmt = (x, d = 2) => (x == null || Number.isNaN(x) ? "–" : Number(x).toFixed(d));
const normLon = (lon) => ((((lon + 180) % 360) + 360) % 360) - 180;

let toastTimer;
function toast(msg) {
  const el = $("#toast");
  el.textContent = msg;
  el.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("show"), 3200);
}

// ------------------------------------------------------------- page effects
/** Hide every logo slot if the logo image is missing, instead of showing broken images. */
function setupLogo() {
  const img = $(".brand-logo");
  if (!img) return;
  const missing = () => document.documentElement.classList.add("no-logo");
  if (img.complete && img.naturalWidth === 0) missing();
  else img.addEventListener("error", missing, { once: true });
}

const revealObserver = "IntersectionObserver" in window
  ? new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) { e.target.classList.add("in"); revealObserver.unobserve(e.target); } });
    }, { threshold: 0.12, rootMargin: "0px 0px -40px 0px" })
  : null;
function observeReveals(root = document) {
  $$(".reveal:not(.in)", root).forEach((el) => (revealObserver ? revealObserver.observe(el) : el.classList.add("in")));
}

function setupNav() {
  const nav = $("#nav");
  const onScroll = () => nav.classList.toggle("scrolled", window.scrollY > 30);
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  const steps = $$(".step");
  if (!("IntersectionObserver" in window)) return;
  const obs = new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting) steps.forEach((s) => s.classList.toggle("is-active", s.dataset.step === e.target.id));
    });
  }, { threshold: 0.3 });
  ["#priorities", "#target", "#results", "#how"].forEach((id) => obs.observe($(id)));
}

// --------------------------------------------------------------- priorities
function renderCriteria() {
  const grid = $("#criteriaGrid");
  grid.innerHTML = "";
  CATEGORIES.forEach((cat) => {
    const block = document.createElement("div");
    block.className = "category-block";
    block.style.setProperty("--cat", cat.color);
    block.innerHTML = `<h3 class="category-title reveal">${esc(cat.name)}</h3><div class="category-cards"></div>`;
    const cards = $(".category-cards", block);
    CRITERIA.forEach((c, k) => {
      if (c.category !== cat.id) return;
      const card = document.createElement("article");
      card.className = "panel crit-card reveal";
      card.innerHTML = `
        <div class="crit-head">
          <label for="sl-${c.id}">${esc(c.name)}</label>
          <output class="crit-value" id="val-${c.id}" for="sl-${c.id}"></output>
          <button type="button" class="info-btn" aria-expanded="false" aria-controls="info-${c.id}" aria-label="About ${esc(c.name)}">i</button>
        </div>
        <input class="slider" id="sl-${c.id}" type="range" min="0" max="1" step="0.05" data-k="${k}" />
        <div class="crit-info" id="info-${c.id}" hidden>
          <ul class="crit-items">${c.measures.map((m) => `<li>${esc(m)}</li>`).join("")}</ul>
          <p>${esc(c.rationale)}</p>
          <dl>
            <dt>Earth</dt><dd>${c.earth.map(esc).join("<br>")}</dd>
            <dt>Mars</dt><dd>${c.mars.map(esc).join("<br>")}</dd>
            <dt>Rule</dt><dd>${esc(RULES[c.rule.type].label)}</dd>
          </dl>
          ${c.note ? `<p class="crit-note">${esc(c.note)}</p>` : ""}
        </div>`;
      cards.appendChild(card);
    });
    grid.appendChild(block);
  });

  $$(".info-btn", grid).forEach((btn) => btn.addEventListener("click", () => {
    const info = document.getElementById(btn.getAttribute("aria-controls"));
    const open = info.hidden;
    info.hidden = !open;
    btn.setAttribute("aria-expanded", String(open));
  }));
  $$(".slider", grid).forEach((sl) => {
    sl.addEventListener("input", () => { state.importance[+sl.dataset.k] = +sl.value; syncSliders(); });
    sl.addEventListener("change", () => { if (state.result) runAnalysis({ quiet: true }); });
  });

  const presets = $("#presets");
  Object.keys(PRESETS).forEach((name) => {
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = name;
    b.addEventListener("click", () => {
      state.importance = [...PRESETS[name]];
      syncSliders();
      if (state.result) runAnalysis({ quiet: true });
    });
    presets.appendChild(b);
  });
  syncSliders();
}

function syncSliders() {
  CRITERIA.forEach((c, k) => {
    const v = state.importance[k];
    const sl = $(`#sl-${c.id}`);
    sl.value = v;
    sl.style.setProperty("--pct", `${v * 100}%`);
    sl.closest(".crit-card").classList.toggle("is-off", v === 0);
    $(`#val-${c.id}`).textContent = fmt(v);
  });
  $$("#presets button").forEach((b) => {
    const p = PRESETS[b.textContent];
    b.classList.toggle("is-active", p.every((v, k) => Math.abs(v - state.importance[k]) < 1e-9));
  });
  updateRunButton();
}

function updateRunButton() {
  const allZero = state.importance.every((v) => v === 0);
  $("#runBtn").disabled = !state.target || allZero;
}

// -------------------------------------------------------------- mars target
function renderQuickPicks() {
  const wrap = $("#quickPicks");
  const picks = ["Jezero Crater", "Gale Crater", "Arsia Mons", "Phoenix landing site", "Hellas Planitia", "Meridiani Planum", "Mawrth Vallis", "Arcadia Planitia"];
  picks.forEach((name) => {
    const r = state.data.marsRegions.find((x) => x.name === name);
    if (!r) return;
    const b = document.createElement("button");
    b.type = "button";
    b.className = "chip";
    b.textContent = name;
    b.addEventListener("click", () => setTarget(r.lat, r.lon, { fly: true }));
    wrap.appendChild(b);
  });
}

function setTarget(lat, lon, { fly = false } = {}) {
  lon = normLon(lon);
  const { values, neighbors } = marsProfileAt(lat, lon, state.data.marsRegions, CRITERIA_IDS);
  state.target = { lat, lon, profile: values, neighbors };
  $("#latInput").value = lat.toFixed(2);
  $("#lonInput").value = lon.toFixed(2);
  $("#coordError").textContent = "";
  state.mars?.setTarget(lat, lon, fly);
  $$("#quickPicks .chip").forEach((c) => {
    const r = state.data.marsRegions.find((x) => x.name === c.textContent);
    c.classList.toggle("is-active", Boolean(r) && Math.abs(r.lat - lat) < 1e-6 && Math.abs(r.lon - lon) < 1e-6);
  });

  const readout = $("#targetReadout");
  readout.hidden = false;
  readout.innerHTML = `
    <div class="coord-big">${fmtLat(lat)}, ${fmtLon(lon)}</div>
    <p class="near">${esc(neighbors[0].r.name)}</p>
    <div class="profile-list">
      ${CRITERIA.map((c) => `
        <div class="profile-row" style="--cat:${categoryOf(c).color}">
          <span>${esc(c.short)}</span><span class="bar"><i data-w="${values[c.id] * 100}"></i></span><span class="v">${fmt(values[c.id])}</span>
        </div>`).join("")}
    </div>`;
  requestAnimationFrame(() => requestAnimationFrame(() => {
    $$(".profile-row i", readout).forEach((i) => { i.style.width = `${i.dataset.w}%`; });
  }));
  updateRunButton();
  // Results follow the target immediately; the button only jumps to them.
  if (!state.importance.every((v) => v === 0)) runAnalysis({ quiet: Boolean(state.result) });
}

function setupCoordForm() {
  // Plain button + Enter key instead of a form element: sandboxed embeds block form submission.
  const submit = () => {
    const lat = parseFloat($("#latInput").value);
    const lon = parseFloat($("#lonInput").value);
    const err = $("#coordError");
    if (!Number.isFinite(lat) || lat < -90 || lat > 90) { err.textContent = "Latitude: −90 to 90"; return; }
    if (!Number.isFinite(lon) || lon < -180 || lon > 180) { err.textContent = "Longitude: −180 to 180"; return; }
    setTarget(lat, lon, { fly: true });
  };
  $("#coordSetBtn").addEventListener("click", submit);
  ["#latInput", "#lonInput"].forEach((id) => $(id).addEventListener("keydown", (e) => {
    if (e.key === "Enter") { e.preventDefault(); submit(); }
  }));
}

function initMarsWhenNear() {
  const shell = $("#marsViewer");
  const loading = $("#marsLoading");
  const cursor = $("#marsCursor");
  if (!cesiumAvailable()) {
    loading.classList.add("error");
    loading.innerHTML = "<p>3D globe unavailable</p>";
    return;
  }
  let started = false;
  const start = async () => {
    if (started) return;
    started = true;
    try {
      state.mars = await createMarsViewer(shell, {
        regions: state.data.marsRegions,
        onPick: (lat, lon) => setTarget(lat, lon, { fly: false }),
        onStatus: (src) => { $("#marsSource").textContent = src; },
        // Live coordinates under the cursor.
        onHover: (ll, pos) => {
          if (!ll) { cursor.hidden = true; return; }
          cursor.textContent = `${fmtLat(ll.lat)}  ${fmtLon(ll.lon)}`;
          cursor.style.left = `${pos.x}px`;
          cursor.style.top = `${pos.y}px`;
          cursor.hidden = false;
        },
      });
      if (state.target) state.mars.setTarget(state.target.lat, state.target.lon, false);
      loading.classList.add("done");
    } catch (err) {
      console.error(err);
      loading.classList.add("error");
      loading.innerHTML = `<p>Mars globe failed: ${esc(err.message || err)}</p>`;
    }
  };
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(([e]) => { if (e.isIntersecting) { io.disconnect(); start(); } }, { rootMargin: "800px 0px" });
    io.observe(shell);
  } else start();
}

// ---------------------------------------------------------------- analysis
function runAnalysis({ quiet = false } = {}) {
  if (!state.target) return;
  if (state.importance.every((v) => v === 0)) return;
  const { sites, grid } = state.data;
  const res = scoreLocations([...sites, ...grid], state.target.profile, state.importance, CRITERIA);
  const scoredSites = res.scored.filter((l) => l.kind === "site");
  const top = topN(scoredSites, 5);
  state.result = { ...res, sites: scoredSites, top };
  if (!state.selectedId || !scoredSites.some((s) => s.id === state.selectedId) || !quiet) state.selectedId = top[0].id;

  const section = $("#results");
  const firstTime = section.classList.contains("is-hidden");
  section.classList.remove("is-hidden");
  $('.step[data-step="results"]').classList.remove("is-locked");
  // Reveal directly instead of waiting on the scroll observer, so results
  // always appear even while the globes are busy on slower GPUs.
  $$(".reveal", section).forEach((el) => el.classList.add("in"));
  $("#demoBadge").hidden = !state.data.isDemo;

  renderTopCards();
  renderDetail();
  renderCharts();
  ensureEarth().then((earth) => {
    if (!earth) return;
    earth.setTopMarkers(top);
    applyLayer();
    if (firstTime || !quiet) earth.flyTo(top[0].lat, top[0].lon);
  });
}

function renderTopCards() {
  const wrap = $("#topCards");
  wrap.innerHTML = state.result.top.map((s, i) => `
    <button type="button" class="panel top-card" data-id="${esc(s.id)}">
      <div class="top-head"><span class="rank">${i + 1}</span><strong class="top-score">${fmt(s.total, 3)}</strong></div>
      <div class="score-bar"><i data-w="${s.total * 100}"></i></div>
      <h4>${esc(s.name.split(",")[0])}</h4>
      <p class="where">${esc(s.country)}</p>
      <div class="mini-bars" aria-hidden="true">
        ${CRITERIA.map((c) => `<i style="--cat:${categoryOf(c).color}" data-h="${(s.scores[c.id] ?? 0) * 100}" title="${esc(c.short)}: ${fmt(s.scores[c.id])}"></i>`).join("")}
      </div>
    </button>`).join("");
  requestAnimationFrame(() => requestAnimationFrame(() => {
    $$(".score-bar i", wrap).forEach((b) => { b.style.width = `${b.dataset.w}%`; });
    $$(".mini-bars i", wrap).forEach((b) => { b.style.height = `${b.dataset.h}%`; });
  }));
  $$(".top-card", wrap).forEach((card) => {
    card.addEventListener("click", () => selectLocation(card.dataset.id, { fly: true }));
  });
  highlightSelected();
}

function highlightSelected() {
  $$(".top-card").forEach((c) => c.classList.toggle("is-selected", c.dataset.id === state.selectedId));
}

function findLocation(id) {
  return state.result.scored.find((l) => l.id === id);
}

function selectLocation(id, { fly = false } = {}) {
  const loc = findLocation(id);
  if (!loc) return;
  state.selectedId = id;
  highlightSelected();
  renderDetail();
  drawMetric(state.result.sites, $("#metricSelect").value, state.selectedId);
  if (fly) state.earth?.flyTo(loc.lat, loc.lon);
}

function renderDetail() {
  const loc = findLocation(state.selectedId);
  const panel = $("#detailPanel");
  if (!loc) { panel.innerHTML = ""; return; }
  const title = loc.kind === "site" ? loc.name.split(",")[0] : `${fmtLat(loc.lat)}, ${fmtLon(loc.lon)}`;
  panel.innerHTML = `
    <h3 class="detail-title">${esc(title)}</h3>
    <p class="where">${loc.country ? esc(loc.country) : "Grid cell"}</p>
    <div class="detail-total"><strong>${fmt(loc.total, 3)}</strong></div>
    <div class="chart-box"><canvas id="profileChart" aria-label="Similarity per criterion compared with the mean of all tested locations" role="img"></canvas></div>
    <div class="table-wrap"><table class="score-table">
      <thead><tr><th>Criterion</th><th>Score</th><th>Weight</th></tr></thead>
      <tbody>
      ${CRITERIA.map((c, k) => `<tr style="--cat:${categoryOf(c).color}"><td><span class="dot"></span>${esc(c.short)}</td><td>${fmt(loc.scores[c.id], 3)}</td><td>${fmt(state.result.weights[k], 3)}</td></tr>`).join("")}
      </tbody>
    </table></div>`;
  drawProfile(loc, state.result.means);
}

function renderCharts() {
  const { top, sites, scored, weights } = state.result;
  drawGrouped(top);
  drawMetric(sites, $("#metricSelect").value, state.selectedId);
  drawWeights(weights);
  drawScatter(scored, top, $("#scatterX").value, $("#scatterY").value);
}

function setupChartControls() {
  const options = [["total", "Total score"], ...CRITERIA.map((c) => [c.id, c.name])];
  const fill = (sel, value) => {
    sel.innerHTML = options.map(([v, l]) => `<option value="${v}">${esc(l)}</option>`).join("");
    sel.value = value;
  };
  fill($("#metricSelect"), "total");
  fill($("#scatterX"), "geology");
  fill($("#scatterY"), "total");
  $("#metricSelect").addEventListener("change", () => state.result && drawMetric(state.result.sites, $("#metricSelect").value, state.selectedId));
  ["#scatterX", "#scatterY"].forEach((id) => $(id).addEventListener("change", () => {
    if (state.result) drawScatter(state.result.scored, state.result.top, $("#scatterX").value, $("#scatterY").value);
  }));
}

/** Method section: scoring rule per criterion. */
function renderRules() {
  const rule = (c) => {
    const r = RULES[c.rule.type];
    const extra = c.rule.type === "gap" ? `, scale ${c.rule.scale}` : c.rule.type === "match" ? `, present ≥ ${c.rule.threshold}` : "";
    return `<td>${esc(r.label)}</td><td><code>${esc(r.formula)}${esc(extra)}</code></td>`;
  };
  $("#rulesTable").innerHTML = `
    <thead><tr><th>Criterion</th><th>Rule</th><th>s<sub>ik</sub></th></tr></thead>
    <tbody>${CRITERIA.map((c) => `<tr><td>${esc(c.name)}</td>${rule(c)}</tr>`).join("")}</tbody>`;
}

// ------------------------------------------------------------------ earth
function setupLayerPicker() {
  const wrap = $("#layerPicker");
  const layers = [["total", "Total"], ...CRITERIA.map((c) => [c.id, c.short])];
  wrap.innerHTML = layers.map(([id, label]) => `<button type="button" class="chip${id === state.layer ? " is-active" : ""}" data-layer="${id}">${esc(label)}</button>`).join("");
  $$(".chip", wrap).forEach((b) => b.addEventListener("click", () => {
    state.layer = b.dataset.layer;
    $$(".chip", wrap).forEach((x) => x.classList.toggle("is-active", x === b));
    $("#metricSelect").value = state.layer;
    if (state.result) drawMetric(state.result.sites, state.layer, state.selectedId);
    applyLayer();
  }));
  $$("#viewToggle button").forEach((b) => b.addEventListener("click", () => {
    state.mode = b.dataset.mode;
    $$("#viewToggle button").forEach((x) => x.classList.toggle("is-active", x === b));
    applyLayer();
  }));
}

function applyLayer() {
  if (!state.earth || !state.result) return;
  const metric = state.layer;
  const valueOf = (l) => (metric === "total" ? l.total : l.scores[metric]);
  state.earth.setMode(state.mode);
  const { min, max } = state.earth.setBars(state.result.scored, valueOf);
  $("#legend").innerHTML = `
    <h5>${esc(metricLabel(metric))}</h5>
    <div class="ramp"></div>
    <div class="ticks"><span>${fmt(min)}</span><span>${fmt((min + max) / 2)}</span><span>${fmt(max)}</span></div>`;
}

function ensureEarth() {
  if (state.earthPromise) return state.earthPromise;
  const loading = $("#earthLoading");
  if (!cesiumAvailable()) {
    loading.classList.add("error");
    loading.innerHTML = "<p>3D globe unavailable</p>";
    state.earthPromise = Promise.resolve(null);
    return state.earthPromise;
  }
  const tooltip = $("#earthTooltip");
  state.earthPromise = createEarthViewer($("#earthViewer"), {
    coastlines: state.data.coastlines,
    gridStep: state.data.gridStep,
    onHover: (loc, pos) => {
      if (!loc) { tooltip.hidden = true; return; }
      const v = state.layer === "total" ? loc.total : loc.scores[state.layer];
      const name = loc.kind === "site" ? loc.name.split(",")[0] : `${fmtLat(loc.lat)}, ${fmtLon(loc.lon)}`;
      tooltip.innerHTML = `<b>${esc(name)}</b><span>${esc(metricLabel(state.layer))}</span><strong>${fmt(v, 3)}</strong>`;
      tooltip.style.left = `${pos.x}px`;
      tooltip.style.top = `${pos.y}px`;
      tooltip.hidden = false;
    },
    onPick: (loc) => { if (loc?.id) selectLocation(loc.id); },
  }).then((earth) => {
    state.earth = earth;
    loading.classList.add("done");
    return earth;
  }).catch((err) => {
    console.error(err);
    loading.classList.add("error");
    loading.innerHTML = `<p>Earth globe failed: ${esc(err.message || err)}</p>`;
    return null;
  });
  return state.earthPromise;
}

// ------------------------------------------------------------------- boot
async function boot() {
  startStarfield($("#starfield"));
  setupLogo();
  observeReveals();
  setupNav();
  initIon();
  setupChartDefaults();
  setupChartControls();
  setupLayerPicker();
  setupCoordForm();
  renderRules();
  $("#runBtn").addEventListener("click", () => $("#results").scrollIntoView({ behavior: "smooth", block: "start" }));

  try {
    state.data = await loadData();
  } catch (err) {
    console.error(err);
    toast("Could not load the analog dataset.");
    return;
  }
  $("#statCriteria").textContent = CRITERIA.length;
  $("#statSites").textContent = state.data.sites.length;
  $("#statGrid").textContent = state.data.grid.length.toLocaleString("en-US");
  $("#statStep").textContent = `${state.data.gridStep}° × ${state.data.gridStep}°`;
  $("#statRegions").textContent = state.data.marsRegions.length;

  renderCriteria();
  renderQuickPicks();
  observeReveals();
  initMarsWhenNear();
}

boot();

// Exposed for debugging in the browser console.
window.__analog = { state, TOP_COLORS, angularDistance };
