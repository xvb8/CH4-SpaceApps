import { CRITERIA, CATEGORIES, CRITERIA_IDS, PRESETS, RULES, categoryOf } from "./criteria.js";
import { loadData } from "./data.js";
import { marsProfileAt, scoreLocations, topN, angularDistance } from "./scoring.js";
import { startStarfield } from "./background.js";
import { cesiumAvailable, initIon, createMarsViewer, createEarthViewer } from "./globes.js";
import { photosAvailable, imagesFor, mountStreetView, onGoogleDenied } from "./photos.js";
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

/**
 * Scroll-linked fade: each .reveal block gets --reveal from 0 to 1 as it moves
 * up the viewport. The CSS mask uses it so a block's top appears before its
 * bottom. On load, blocks already on screen fade in over time, top to bottom.
 * Once fully shown a block stays shown.
 */
const REVEAL_MS = 1400;
let revealT0 = 0, revealRaf = 0;
function updateReveals(now = performance.now()) {
  revealRaf = 0;
  const vh = window.innerHeight;
  let pending = false;
  $$(".reveal:not(.in)").forEach((el) => {
    const r = el.getBoundingClientRect();
    if (!r.height) return;   // hidden (e.g. results before the first run)
    const byScroll = (vh - r.top) / (Math.min(r.height, vh * 0.8) + vh * 0.25);
    const byTime = (now - revealT0 - Math.max(0, r.top) * 0.6) / REVEAL_MS;
    const p = Math.max(0, Math.min(1, byScroll, byTime));
    if (p >= 1) { el.classList.add("in"); el.style.removeProperty("--reveal"); return; }
    el.style.setProperty("--reveal", p.toFixed(3));
    if (byTime < 1 && byScroll >= 1) pending = true;   // still animating on its own
  });
  if (pending) revealRaf = requestAnimationFrame(updateReveals);
}
function observeReveals() {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    $$(".reveal").forEach((el) => el.classList.add("in"));
    return;
  }
  if (!revealT0) {
    revealT0 = performance.now();
    window.addEventListener("scroll", () => { if (!revealRaf) revealRaf = requestAnimationFrame(updateReveals); }, { passive: true });
    window.addEventListener("resize", () => { if (!revealRaf) revealRaf = requestAnimationFrame(updateReveals); });
  }
  if (!revealRaf) revealRaf = requestAnimationFrame(updateReveals);
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
  CATEGORIES.forEach((cat, i) => {
    const block = document.createElement("div");
    block.className = "category-block";
    block.id = `page-${cat.id}`;
    block.setAttribute("role", "group");
    block.setAttribute("aria-label", cat.name);
    block.style.setProperty("--cat", cat.color);
    block.innerHTML = `<h3 class="category-title">${i + 1}. ${esc(cat.name)}</h3><div class="category-cards"></div>`;
    const cards = $(".category-cards", block);
    CRITERIA.forEach((c, k) => {
      if (c.category !== cat.id) return;
      const card = document.createElement("article");
      card.className = "crit-card";
      card.innerHTML = `
        <div class="crit-text">
          <label for="sl-${c.id}">${esc(c.name)}</label>
          <p class="crit-measures">${esc(c.measures.join(", "))}</p>
        </div>
        <input class="slider" id="sl-${c.id}" type="range" min="0" max="1" step="0.05" data-k="${k}" />
        <output class="crit-value" id="val-${c.id}" for="sl-${c.id}"></output>
        <button type="button" class="info-btn" aria-expanded="false" aria-controls="info-${c.id}" aria-label="About ${esc(c.name)}">i</button>
        <div class="crit-info" id="info-${c.id}" role="region" aria-label="${esc(c.name)} details">
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

  // Info opens as a dropdown over the cards below (no layout change); one open at a time.
  const closeInfo = (except) => $$(".crit-card.is-open", grid).forEach((card) => {
    if (card === except) return;
    card.classList.remove("is-open");
    $(".info-btn", card).setAttribute("aria-expanded", "false");
  });
  $$(".info-btn", grid).forEach((btn) => btn.addEventListener("click", (e) => {
    e.stopPropagation();
    const card = btn.closest(".crit-card");
    closeInfo(card);
    const open = card.classList.toggle("is-open");
    btn.setAttribute("aria-expanded", String(open));
  }));
  document.addEventListener("click", (e) => { if (!e.target.closest(".crit-info")) closeInfo(); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeInfo(); });
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
  setupPages();
  syncSliders();
}

/**
 * Priorities as a paged form: one category per page, a step bar to go back to
 * any page already visited, and Back/Next. Next on the last page moves on to
 * the Mars target.
 */
function setupPages() {
  const steps = $("#formSteps"), blocks = $$(".category-block");
  const prev = $("#pagePrev"), next = $("#pageNext");
  let page = 0, furthest = 0;
  steps.innerHTML = CATEGORIES.map((cat, i) =>
    `<li><button type="button" data-page="${i}" aria-controls="page-${cat.id}">${i + 1}<span>. ${esc(cat.name)}</span></button></li>`).join("");
  const stepBtns = $$("button", steps);

  const show = (i, { scroll = true } = {}) => {
    page = i;
    furthest = Math.max(furthest, i);
    blocks.forEach((b, k) => {
      b.classList.toggle("is-current", k === i);
      b.inert = k !== i;
      // Earlier pages wait off to the left, later ones to the right, so pages slide in the direction of travel.
      b.style.setProperty("--from", `${(k < i ? -1 : 1) * 24}px`);
    });
    stepBtns.forEach((b, k) => {
      if (k === i) b.setAttribute("aria-current", "step"); else b.removeAttribute("aria-current");
      b.classList.toggle("is-done", k < furthest && k !== i);
      b.disabled = k > furthest;
    });
    prev.disabled = i === 0;
    const last = i === blocks.length - 1;
    next.textContent = last ? "Mars target" : "Next";
    $("#pageCount").textContent = `${i + 1} of ${blocks.length}`;
    if (scroll) {
      const top = $("#priorities").getBoundingClientRect().top;
      if (top < -40) $("#priorities").scrollIntoView({ behavior: "smooth", block: "start" });
    }
  };
  stepBtns.forEach((b) => b.addEventListener("click", () => show(+b.dataset.page)));
  prev.addEventListener("click", () => show(Math.max(0, page - 1)));
  next.addEventListener("click", () => {
    if (page < blocks.length - 1) show(page + 1);
    else $("#target").scrollIntoView({ behavior: "smooth", block: "start" });
  });
  show(0, { scroll: false });
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
  // Newly shown results fade in as they scroll into view.
  observeReveals();
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
      ${photosAvailable() ? `<div class="card-photo" data-lat="${s.lat}" data-lon="${s.lon}"><div class="view-img"><img alt="" /></div></div>` : ""}
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
  // Each card shows a ground-level image when one exists near its coordinates, else the satellite view.
  $$(".card-photo", wrap).forEach((slot) => {
    const lat = +slot.dataset.lat, lon = +slot.dataset.lon;
    showImage(slot, () => imagesFor(lat, lon).then((r) => (r ? [r.ground, r.satellite] : [])), { interactive: false });
  });
  highlightSelected();
}

/**
 * Show the first candidate image that loads in `slot` (an element holding a
 * .view-img with an <img>); remove the slot when none do. Street View tries
 * the Static image, then a Maps JavaScript panorama (always the panorama when
 * `interactive`, so it can be looked around). If Google rejects the key after
 * a panorama has been drawn, the panorama is removed and the slot is filled
 * again from the remaining sources.
 */
async function showImage(slot, getCandidates, { interactive = false } = {}) {
  const box = $(".view-img", slot), img = $("img", box);
  const loadImg = (src) => new Promise((resolve) => {
    img.onload = () => resolve(true);
    img.onerror = () => resolve(false);
    img.src = src;
  });
  const candidates = await getCandidates();
  for (const im of candidates.filter(Boolean)) {
    if (!slot.isConnected) return;
    let ok = false;
    if (im.kind === "streetview") {
      if (!interactive) ok = await loadImg(im.src);
      if (!ok) {
        img.removeAttribute("src");
        const pano = document.createElement("div");
        pano.className = "pano";
        box.appendChild(pano);
        ok = await mountStreetView(pano, im, { interactive });
        if (!ok) { pano.remove(); continue; }
        onGoogleDenied(() => {
          pano.remove();
          slot.classList.remove("is-loaded");
          if (slot.isConnected) showImage(slot, getCandidates, { interactive });
        });
      }
    } else {
      ok = await loadImg(im.src);
    }
    if (ok && slot.isConnected) { slot.classList.add("is-loaded"); return; }
  }
  if (slot.isConnected) slot.remove();
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
    ${photosAvailable() ? `<div class="detail-views">
      <div class="view" data-kind="ground"><div class="view-img"><img alt="Ground-level view near ${esc(title)}" /></div></div>
      <div class="view" data-kind="satellite"><div class="view-img"><img alt="Satellite view of ${esc(title)}" /></div></div>
    </div>` : ""}
    <div class="chart-box"><canvas id="profileChart" aria-label="Similarity per criterion compared with the mean of all tested locations" role="img"></canvas></div>
    <div class="table-wrap"><table class="score-table">
      <thead><tr><th>Criterion</th><th>Score</th><th>Weight</th></tr></thead>
      <tbody>
      ${CRITERIA.map((c, k) => `<tr style="--cat:${categoryOf(c).color}"><td><span class="dot"></span>${esc(c.short)}</td><td>${fmt(loc.scores[c.id], 3)}</td><td>${fmt(state.result.weights[k], 3)}</td></tr>`).join("")}
      </tbody>
    </table></div>`;
  drawProfile(loc, state.result.means);
  if (photosAvailable()) renderDetailViews(loc);
}

function renderDetailViews(loc) {
  const views = $(".detail-views");
  const images = () => imagesFor(loc.lat, loc.lon);
  showImage($('.view[data-kind="ground"]', views), () => images().then((r) => [r?.ground]), { interactive: true });
  showImage($('.view[data-kind="satellite"]', views), () => images().then((r) => [r?.satellite]));
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
