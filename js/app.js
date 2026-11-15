import { CRITERIA, CATEGORIES, CRITERIA_IDS, PRESETS, categoryOf } from "./criteria.js";
import { loadData } from "./data.js";
import { marsProfileAt, scoreLocations, topN, angularDistance } from "./scoring.js";
import { startStarfield } from "./background.js";
import { cesiumAvailable, initIon, createMarsViewer, createEarthViewer } from "./globes.js";
import {
  setupChartDefaults, drawGrouped, drawMetric, drawWeights, drawScatter, drawRadar, metricLabel, TOP_COLORS,
} from "./charts.js";

const MARS_RADIUS_KM = 3389.5;
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

const state = {
  data: null,
  importance: [...PRESETS.Balanced],
  target: null,        // { lat, lon, profile, neighbors }
  result: null,        // { scored, means, spread, weights, top, sites }
  selectedId: null,
  layer: "total",
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
const fmt = (x, d = 2) => Number(x).toFixed(d);
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
function splitTitle() {
  $$("[data-split]").forEach((el) => {
    const text = el.textContent;
    el.textContent = "";
    el.setAttribute("aria-label", text);
    [...text].forEach((ch, i) => {
      const span = document.createElement("span");
      span.setAttribute("aria-hidden", "true");
      if (ch === " ") { span.className = "split-space"; }
      else { span.className = "split-char"; span.textContent = ch; span.style.setProperty("--i", i); }
      el.appendChild(span);
    });
  });
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
  new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (!e.isIntersecting) return;
      steps.forEach((s) => s.classList.toggle("is-active", s.dataset.step === e.target.id));
    });
  }, { threshold: 0.35 }).observe($("#priorities"));
  const obs = new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting) steps.forEach((s) => s.classList.toggle("is-active", s.dataset.step === e.target.id));
    });
  }, { threshold: 0.25 });
  ["#target", "#results"].forEach((id) => obs.observe($(id)));
}

// --------------------------------------------------------------- priorities
function renderCriteria() {
  const grid = $("#criteriaGrid");
  grid.innerHTML = "";
  CATEGORIES.forEach((cat) => {
    const block = document.createElement("div");
    block.className = "category-block";
    block.style.setProperty("--cat", cat.color);
    block.innerHTML = `
      <h3 class="category-title reveal"><span class="cat-icon">${cat.icon}</span>${esc(cat.name)}<span class="cat-avg" data-cat-avg="${cat.id}"></span></h3>
      <div class="category-cards"></div>`;
    const cards = $(".category-cards", block);
    CRITERIA.forEach((c, k) => {
      if (c.category !== cat.id) return;
      const card = document.createElement("article");
      card.className = "glass crit-card reveal";
      card.style.setProperty("--d", `${(cards.children.length % 3) * 0.08}s`);
      card.innerHTML = `
        <div class="crit-head">
          <div><h4>${esc(c.name)}</h4><p>${esc(c.detail)}</p></div>
          <output class="crit-value" id="val-${c.id}" for="sl-${c.id}"></output>
        </div>
        ${c.items.length ? `<ul class="crit-items">${c.items.map((i) => `<li>${esc(i)}</li>`).join("")}</ul>` : ""}
        <input class="slider" id="sl-${c.id}" type="range" min="0" max="1" step="0.05" aria-label="Importance of ${esc(c.name)}" data-k="${k}" />
        <div class="slider-scale"><span>Ignore</span><span>Critical</span></div>
        <details class="crit-more">
          <summary>Rationale &amp; data</summary>
          <div class="more-body">
            <p>${esc(c.rationale)}</p>
            <dl><dt>Earth</dt><dd>${esc(c.earth)}</dd><dt>Mars</dt><dd>${esc(c.mars)}</dd></dl>
          </div>
        </details>`;
      cards.appendChild(card);
    });
    grid.appendChild(block);
  });

  $$(".slider", grid).forEach((sl) => {
    sl.addEventListener("input", () => { state.importance[+sl.dataset.k] = +sl.value; syncSliders(); });
    sl.addEventListener("change", () => { if (state.result) runAnalysis({ scroll: false, quiet: true }); });
  });

  const presets = $("#presets");
  Object.keys(PRESETS).forEach((name) => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "chip";
    b.textContent = name;
    b.addEventListener("click", () => {
      state.importance = [...PRESETS[name]];
      syncSliders();
      if (state.result) runAnalysis({ scroll: false, quiet: true });
    });
    presets.appendChild(b);
  });
  const reset = document.createElement("button");
  reset.type = "button";
  reset.className = "chip";
  reset.textContent = "Reset";
  reset.addEventListener("click", () => { state.importance = new Array(CRITERIA.length).fill(0.5); syncSliders(); });
  presets.appendChild(reset);
  syncSliders();
}

function syncSliders() {
  CRITERIA.forEach((c, k) => {
    const v = state.importance[k];
    const sl = $(`#sl-${c.id}`);
    sl.value = v;
    sl.style.setProperty("--pct", `${v * 100}%`);
    sl.closest(".crit-card").style.setProperty("--val", v);
    $(`#val-${c.id}`).textContent = fmt(v);
  });
  CATEGORIES.forEach((cat) => {
    const vals = CRITERIA.map((c, k) => (c.category === cat.id ? state.importance[k] : null)).filter((v) => v !== null);
    $(`[data-cat-avg="${cat.id}"]`).textContent = `avg ${fmt(vals.reduce((a, b) => a + b, 0) / vals.length)}`;
  });
  $$("#presets .chip").forEach((chip) => {
    const p = PRESETS[chip.textContent];
    chip.classList.toggle("is-active", Boolean(p) && p.every((v, k) => Math.abs(v - state.importance[k]) < 1e-9));
  });
  const ignored = state.importance.filter((v) => v === 0).length;
  const allZero = ignored === CRITERIA.length;
  const hint = $("#priorityHint");
  hint.classList.toggle("warn", allZero);
  hint.textContent = allZero
    ? "Give at least one criterion an importance above 0 to run the search."
    : `${CRITERIA.length - ignored} of ${CRITERIA.length} criteria active${ignored ? ` · ${ignored} ignored` : ""}.`;
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
    c.classList.toggle("is-active", r && Math.abs(r.lat - lat) < 1e-6 && Math.abs(r.lon - lon) < 1e-6);
  });

  const nearest = neighbors[0];
  const km = Math.round(nearest.d * MARS_RADIUS_KM);
  const readout = $("#targetReadout");
  readout.innerHTML = `
    <div class="coord-big">${fmtLat(lat)}, ${fmtLon(lon)}</div>
    <p class="near">${km < 5 ? "At" : `${km.toLocaleString()} km from`} <b>${esc(nearest.r.name)}</b>. ${esc(nearest.r.description)}</p>
    <div class="profile-list">
      ${CRITERIA.map((c) => `
        <div class="profile-row" style="--cat:${categoryOf(c).color}">
          <span>${esc(c.short)}</span><span class="bar"><i data-w="${values[c.id] * 100}"></i></span><span class="v">${fmt(values[c.id])}</span>
        </div>`).join("")}
    </div>
    <p class="readout-note">Estimated Mars profile (0–1 index), blended from the ${neighbors.length} nearest reference regions.</p>`;
  requestAnimationFrame(() => requestAnimationFrame(() => {
    $$(".profile-row i", readout).forEach((i) => { i.style.width = `${i.dataset.w}%`; });
  }));
  updateRunButton();
}

function setupCoordForm() {
  // Plain button + Enter key instead of a form element: sandboxed embeds block form submission.
  const submit = () => {
    const lat = parseFloat($("#latInput").value);
    const lon = parseFloat($("#lonInput").value);
    const err = $("#coordError");
    if (!Number.isFinite(lat) || lat < -90 || lat > 90) { err.textContent = "Latitude must be between −90 and 90."; return; }
    if (!Number.isFinite(lon) || lon < -180 || lon > 180) { err.textContent = "Longitude must be between −180 and 180."; return; }
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
  if (!cesiumAvailable()) {
    loading.classList.add("error");
    loading.innerHTML = "<p>The 3D globe could not load (CesiumJS unavailable). You can still enter coordinates or use the famous sites.</p>";
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
      });
      if (state.target) state.mars.setTarget(state.target.lat, state.target.lon, false);
      loading.classList.add("done");
    } catch (err) {
      console.error(err);
      loading.classList.add("error");
      loading.innerHTML = `<p>Could not start the Mars globe: ${esc(err.message || err)}</p>`;
    }
  };
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(([e]) => { if (e.isIntersecting) { io.disconnect(); start(); } }, { rootMargin: "800px 0px" });
    io.observe(shell);
  } else start();
}

// ---------------------------------------------------------------- analysis
function runAnalysis({ scroll = true, quiet = false } = {}) {
  if (!state.target) { toast("Pick a Mars target first."); return; }
  if (state.importance.every((v) => v === 0)) { toast("Set at least one importance above 0."); return; }
  const { sites, grid } = state.data;
  const all = [...sites, ...grid];
  const res = scoreLocations(all, state.target.profile, state.importance, CRITERIA_IDS);
  const scoredSites = res.scored.filter((l) => l.kind === "site");
  const top = topN(scoredSites, 5);
  state.result = { ...res, sites: scoredSites, top };
  if (!state.selectedId || !scoredSites.some((s) => s.id === state.selectedId) || !quiet) state.selectedId = top[0].id;

  const section = $("#results");
  const firstTime = section.classList.contains("is-hidden");
  section.classList.remove("is-hidden");
  $('.step[data-step="results"]').classList.remove("is-locked");
  $$('.step[data-step="priorities"], .step[data-step="target"]').forEach((s) => s.classList.add("is-done"));
  // Reveal directly instead of waiting on the scroll observer, so results
  // always appear even while the globes are busy on slower GPUs.
  $$(".reveal", section).forEach((el, i) => {
    el.style.setProperty("--d", `${Math.min(i, 6) * 0.08}s`);
    el.classList.add("in");
  });

  const near = state.target.neighbors[0].r.name;
  $("#resultsSummary").textContent =
    `Mars target ${fmtLat(state.target.lat)}, ${fmtLon(state.target.lon)} (near ${near}) · ${all.length.toLocaleString()} Earth locations tested · weighted by your ${state.importance.filter((v) => v > 0).length} active priorities.`;
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

  if (scroll) setTimeout(() => section.scrollIntoView({ behavior: "smooth", block: "start" }), firstTime ? 80 : 0);
  if (quiet) toast("Results updated with your new priorities.");
}

function renderTopCards() {
  const wrap = $("#topCards");
  const C = 2 * Math.PI * 32;
  wrap.innerHTML = state.result.top.map((s, i) => `
    <button type="button" class="glass top-card" data-id="${esc(s.id)}" style="--i:${i}">
      <span class="rank">#${i + 1}</span>
      <div class="ring">
        <svg viewBox="0 0 78 78"><circle class="track" cx="39" cy="39" r="32"/><circle class="val" cx="39" cy="39" r="32" stroke-dasharray="${C}" stroke-dashoffset="${C}" data-off="${C * (1 - s.total)}"/></svg>
        <span>${fmt(s.total)}</span>
      </div>
      <h4>${esc(s.name)}</h4>
      <p class="where">${esc(s.country)} · ${fmtLat(s.lat)}, ${fmtLon(s.lon)}</p>
      <p class="desc">${esc(s.description)}</p>
      <div class="mini-bars" title="Per-criterion similarity">
        ${CRITERIA.map((c) => `<i style="--cat:${categoryOf(c).color}" data-h="${s.scores[c.id] * 100}" title="${esc(c.short)}: ${fmt(s.scores[c.id])}"></i>`).join("")}
      </div>
    </button>`).join("");
  requestAnimationFrame(() => requestAnimationFrame(() => {
    $$(".ring .val", wrap).forEach((c) => { c.style.strokeDashoffset = c.dataset.off; });
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
  const rank = state.result.top.findIndex((t) => t.id === loc.id);
  const overall = [...state.result.scored].sort((a, b) => b.total - a.total).findIndex((l) => l.id === loc.id) + 1;
  panel.innerHTML = `
    <p class="eyebrow" style="margin:0">${rank >= 0 ? `Top analog #${rank + 1}` : loc.kind === "site" ? "Analog site" : "Grid cell"}</p>
    <h3 class="detail-title">${esc(loc.name)}</h3>
    <p class="where">${loc.country ? `${esc(loc.country)} · ` : ""}${fmtLat(loc.lat)}, ${fmtLon(loc.lon)}</p>
    <div class="detail-total"><strong>${fmt(loc.total, 3)}</strong><span>total similarity · rank ${overall.toLocaleString()} of ${state.result.scored.length.toLocaleString()}</span></div>
    <p class="desc">${loc.description ? esc(loc.description) : "Synthetic global grid cell used to map how similarity varies across Earth."}</p>
    <div class="chart-box"><canvas id="radarChart"></canvas></div>
    <div class="table-wrap"><table class="score-table"><tbody>
      ${CRITERIA.map((c, k) => `<tr style="--cat:${categoryOf(c).color}"><td><span class="dot"></span>${esc(c.name)}</td><td>${fmt(loc.scores[c.id], 3)}</td><td style="color:var(--dim);font-weight:600;padding-left:10px">w ${fmt(state.result.weights[k], 3)}</td></tr>`).join("")}
    </tbody></table></div>`;
  drawRadar(loc, state.result.means);
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
}

function applyLayer() {
  if (!state.earth || !state.result) return;
  const metric = state.layer;
  const valueOf = (l) => (metric === "total" ? l.total : l.scores[metric]);
  const { min, max } = state.earth.setBars(state.result.scored, valueOf);
  $("#legend").innerHTML = `
    <h5>${esc(metricLabel(metric))}</h5>
    <div class="ramp"></div>
    <div class="ticks"><span>${fmt(min)}</span><span>${fmt((min + max) / 2)}</span><span>${fmt(max)}</span></div>
    <p>Bar height &amp; color = similarity to the Mars target (stretched to the tested range).</p>`;
}

function ensureEarth() {
  if (state.earthPromise) return state.earthPromise;
  const loading = $("#earthLoading");
  if (!cesiumAvailable()) {
    loading.classList.add("error");
    loading.innerHTML = "<p>The 3D Earth could not load (CesiumJS unavailable). Charts and rankings are still available below.</p>";
    state.earthPromise = Promise.resolve(null);
    return state.earthPromise;
  }
  const tooltip = $("#earthTooltip");
  state.earthPromise = createEarthViewer($("#earthViewer"), {
    onHover: (loc, pos) => {
      if (!loc) { tooltip.hidden = true; return; }
      const v = state.layer === "total" ? loc.total : loc.scores[state.layer];
      tooltip.innerHTML = `<b>${esc(loc.name)}</b>${fmtLat(loc.lat)}, ${fmtLon(loc.lon)}<br>${esc(metricLabel(state.layer))}: <b style="display:inline">${fmt(v, 3)}</b>${state.layer !== "total" ? ` · Total ${fmt(loc.total, 3)}` : ""}`;
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
    loading.innerHTML = `<p>Could not start the Earth globe: ${esc(err.message || err)}</p>`;
    return null;
  });
  return state.earthPromise;
}

// ------------------------------------------------------------------- boot
async function boot() {
  startStarfield($("#starfield"));
  splitTitle();
  observeReveals();
  setupNav();
  initIon();
  setupChartDefaults();
  setupChartControls();
  setupLayerPicker();
  setupCoordForm();
  $("#runBtn").addEventListener("click", () => runAnalysis());

  try {
    state.data = await loadData();
  } catch (err) {
    console.error(err);
    toast("Could not load the analog dataset.");
    return;
  }
  $("#statCriteria").textContent = CRITERIA.length;
  $("#statSites").textContent = state.data.sites.length;
  $("#statGrid").textContent = `${(state.data.grid.length / 1000).toFixed(1)}k`;

  renderCriteria();
  renderQuickPicks();
  observeReveals();
  initMarsWhenNear();
}

boot();

// Exposed for debugging in the browser console.
window.__analog = { state, TOP_COLORS, angularDistance };
