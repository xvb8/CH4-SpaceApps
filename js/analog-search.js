// JS port of analog_search.py. Find the best Earth analogs for a Mars target
// without scoring every Earth grid cell.
//
// Pipeline (see pipeline.md and docs/analog_search_journey.md):
//   data -> parsing -> s_ik per criterion -> w_k from std dev + importance
//        -> final score S_i -> pruned search and sorting -> Earth analogs
//
// 1. Weights. v_k is estimated from a random sample of Earth cells, then
//    w_k is frozen so every candidate is compared with the same ruler.
// 2. Hard filters. Cells whose similarity on a required criterion is below
//    a minimum are dropped.
// 3. Zoom pyramid. Earth cells are grouped into step, 2*step, 4*step, ...
//    blocks storing the min / max raw value of each criterion (cheap, coarse).
// 4. Branch and bound. A block's upper bound is the best Gower average its
//    criteria could reach given those min / max values. Blocks are opened
//    best-bound first; any block whose bound is below the current K-th
//    best score is pruned. Result is exact for the frozen weights.
// 5. Cheap criteria first. Full-resolution cells are scored criterion by
//    criterion, cheapest / heaviest first. Unscored criteria are assumed
//    1; scoring stops once that bound drops below the K-th best.
//
// Scoring primitives come from js/scoring.js (similarity, criterionMeans,
// criterionSpread, missionWeights), so this file always agrees with the
// rest of the UI and with site_weights.py.

import {
  similarity, criterionMeans, criterionSpread, missionWeights,
} from "./scoring.js";
import { CRITERION_COST, HARD_FILTERS } from "./criteria.js";

const DEFAULTS = {
  sampleSize: 200,
  randomSeed: 42,
  pyramidLevels: 5,
  topK: 5,
  hardFilters: HARD_FILTERS,
  criterionCost: CRITERION_COST,
};

// ---------- deterministic RNG (mulberry32), so results don't drift between runs ----------
function mulberry32(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6D2B79F5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function sampleIndices(n, k, seed) {
  const rand = mulberry32(seed);
  const idx = Array.from({ length: n }, (_, i) => i);
  // Partial Fisher–Yates: shuffle only the first k positions.
  for (let i = 0; i < Math.min(k, n); i++) {
    const j = i + Math.floor(rand() * (n - i));
    [idx[i], idx[j]] = [idx[j], idx[i]];
  }
  return idx.slice(0, Math.min(k, n));
}

// ---------- frozen weights from a sample ----------
/**
 * Freeze mission weights w_k from a random sample of Earth cells.
 * Returns { weights, spread, means, sampleSize, criterionEvals }.
 */
export function frozenWeights(cells, target, importance, criteria, opts = {}) {
  const { sampleSize = DEFAULTS.sampleSize, randomSeed = DEFAULTS.randomSeed } = opts;
  const K = criteria.length;
  const idx = sampleIndices(cells.length, sampleSize, randomSeed);
  const S = idx.map((i) => criteria.map((c) => similarity(c.rule, cells[i].values[c.id], target[c.id])));
  const means = criterionMeans(S, K);
  const spread = criterionSpread(S, means);
  const weights = missionWeights(importance, spread);
  let evals = 0;
  for (const row of S) for (const x of row) if (x != null) evals++;
  return { weights, spread, means, sampleSize: idx.length, criterionEvals: evals };
}

// ---------- zoom pyramid and bounds ----------
function blockKey(lat, lon, size) {
  return `${Math.floor((lat + 90) / size)},${Math.floor((lon + 180) / size)}`;
}

/**
 * Build the zoom pyramid. levels=L produces L+1 levels, level 0 = one block
 * per cell, level L = size * 2^L blocks. Each block tracks min/max/count for
 * every criterion.
 */
export function buildPyramid(cells, step, criteria, levels = DEFAULTS.pyramidLevels) {
  const K = criteria.length;
  const pyramid = [];
  for (let lvl = 0; lvl <= levels; lvl++) {
    const size = step * 2 ** lvl;
    const blocks = new Map();
    for (let i = 0; i < cells.length; i++) {
      const c = cells[i];
      const key = blockKey(c.lat, c.lon, size);
      let b = blocks.get(key);
      if (!b) {
        b = { level: lvl, cells: [], lo: new Array(K).fill(null), hi: new Array(K).fill(null),
              nPresent: new Array(K).fill(0), children: new Set() };
        blocks.set(key, b);
      }
      b.cells.push(i);
      for (let k = 0; k < K; k++) {
        const e = c.values[criteria[k].id];
        if (e == null || Number.isNaN(e)) continue;
        b.nPresent[k]++;
        b.lo[k] = b.lo[k] == null ? e : Math.min(b.lo[k], e);
        b.hi[k] = b.hi[k] == null ? e : Math.max(b.hi[k], e);
      }
      if (lvl > 0) b.children.add(blockKey(c.lat, c.lon, step * 2 ** (lvl - 1)));
    }
    pyramid.push(blocks);
  }
  return pyramid;
}

/**
 * Highest rule(e, m) for any e in [lo, hi]. Every rule peaks where e is
 * closest to m, except "basic" / "basicLog" which switch formula at e = 0.
 * So the max is among clamp(m, lo, hi), the two ends and (if 0 is in range) 0.
 */
export function bestSimilarityInRange(rule, lo, hi, m) {
  const cands = new Set([Math.min(Math.max(m, lo), hi), lo, hi]);
  if (lo <= 0 && 0 <= hi) cands.add(0);
  let best = -Infinity;
  for (const e of cands) {
    const s = similarity(rule, e, m);
    if (s != null && s > best) best = s;
  }
  return best === -Infinity ? null : best;
}

/**
 * Max of Σ w·u / Σ w over every present set (forced ∪ any subset of optional).
 * Adding an optional term raises the average only if its u is above the
 * current average, so add them greedily from the largest u.
 */
export function gowerUpperBound(forced, optional) {
  let num = 0, den = 0;
  for (const [w, u] of forced) { num += w * u; den += w; }
  const opt = [...optional].sort((a, b) => b[1] - a[1]);
  for (const [w, u] of opt) {
    if (den === 0 || u > num / den) { num += w * u; den += w; }
  }
  return den ? num / den : 0;
}

/** Upper bound on S_i over every cell in the block; -1 if a hard filter rules it out. */
function blockBound(block, target, weights, criteria, hardFilters) {
  const n = block.cells.length;
  const K = criteria.length;
  const forced = [], optional = [];
  for (let k = 0; k < K; k++) {
    const id = criteria[k].id;
    const hasData = block.nPresent[k] > 0 && target[id] != null;
    const u = hasData ? bestSimilarityInRange(criteria[k].rule, block.lo[k], block.hi[k], target[id]) : null;
    const need = hardFilters[id];
    if (need != null && (u == null || u < need)) return -1;
    if (u == null || weights[k] === 0) continue;
    (block.nPresent[k] === n ? forced : optional).push([weights[k], u]);
  }
  return gowerUpperBound(forced, optional);
}

// ---------- full-resolution scoring ----------
/**
 * Score criteria in `order`; stop once the bound (unscored = 1) drops below
 * cutoff. Returns { total, scores } or null if stopped / filtered out.
 */
function scoreCellStaged(values, target, weights, criteria, order, cutoff, hardFilters, stats) {
  const K = criteria.length;
  // Collect present-and-weighted criteria in the chosen order.
  const present = [];
  for (const k of order) {
    const id = criteria[k].id;
    if (values[id] == null || target[id] == null || weights[k] === 0) continue;
    present.push(k);
  }
  let num = 0, den = 0, remainingW = 0;
  for (const k of present) remainingW += weights[k];
  const scores = {};
  for (const k of present) {
    const id = criteria[k].id;
    const s = similarity(criteria[k].rule, values[id], target[id]);
    stats.criterionEvals++;
    const need = hardFilters[id];
    if (need != null && s < need) return null;
    scores[id] = s;
    num += weights[k] * s;
    den += weights[k];
    remainingW -= weights[k];
    if (cutoff != null && (num + remainingW) / (den + remainingW) < cutoff) {
      stats.stoppedEarly++;
      return null;
    }
  }
  // Required criteria with no data on this cell: fail.
  for (const id of Object.keys(hardFilters)) {
    if (values[id] == null || target[id] == null) return null;
  }
  return { total: den ? num / den : 0, scores };
}

// ---------- heaps (no built-in priority queue in JS) ----------
class MinHeap {
  constructor(cmp) { this.a = []; this.cmp = cmp; }
  get size() { return this.a.length; }
  peek() { return this.a[0]; }
  push(x) {
    this.a.push(x);
    let i = this.a.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (this.cmp(this.a[i], this.a[p]) < 0) {
        [this.a[i], this.a[p]] = [this.a[p], this.a[i]];
        i = p;
      } else break;
    }
  }
  pop() {
    const top = this.a[0];
    const last = this.a.pop();
    if (this.a.length) {
      this.a[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1, r = l + 1;
        let s = i;
        if (l < this.a.length && this.cmp(this.a[l], this.a[s]) < 0) s = l;
        if (r < this.a.length && this.cmp(this.a[r], this.a[s]) < 0) s = r;
        if (s === i) break;
        [this.a[i], this.a[s]] = [this.a[s], this.a[i]];
        i = s;
      }
    }
    return top;
  }
}

// ---------- the search ----------
/**
 * Best-first branch and bound. Returns { top, stats }.
 * `top` is an array of { index, total, scores } sorted desc by total.
 */
export function search(cells, pyramid, target, weights, criteria, opts = {}) {
  const {
    topK = DEFAULTS.topK,
    hardFilters = DEFAULTS.hardFilters,
    criterionCost = DEFAULTS.criterionCost,
  } = opts;
  const K = criteria.length;
  const stats = { blocksBounded: 0, blocksPruned: 0, cellsScored: 0,
                  cellsSkipped: 0, criterionEvals: 0, stoppedEarly: 0 };
  // Cheap and heavy first: highest weight per unit cost.
  const order = Array.from({ length: K }, (_, k) => k)
    .sort((a, b) => (weights[b] / (criterionCost[criteria[b].id] ?? 1))
                  - (weights[a] / (criterionCost[criteria[a].id] ?? 1)));
  // top: min-heap of scored cells; smallest total at root, size <= topK.
  const top = new MinHeap((a, b) => a.total - b.total);
  // queue: max-heap of (bound, level, key); use negative bound in min-heap.
  const queue = new MinHeap((a, b) => a.negBound - b.negBound || a.tie - b.tie);
  let tie = 0;
  const topLevel = pyramid.length - 1;
  for (const [key, b] of pyramid[topLevel]) {
    const bound = blockBound(b, target, weights, criteria, hardFilters);
    stats.blocksBounded++;
    if (bound >= 0) queue.push({ negBound: -bound, tie: tie++, level: topLevel, key });
    else stats.blocksPruned++;
  }
  const cutoff = () => (top.size === topK ? top.peek().total : null);
  while (queue.size) {
    const { negBound, level, key } = queue.pop();
    const c = cutoff();
    if (c != null && -negBound < c) {
      // Best-first: nothing left in the queue can beat the K-th best.
      stats.blocksPruned += 1 + queue.size;
      break;
    }
    const block = pyramid[level].get(key);
    if (level === 0) {
      const i = block.cells[0];
      stats.cellsScored++;
      const r = scoreCellStaged(cells[i].values, target, weights, criteria, order, c, hardFilters, stats);
      if (!r) continue;
      if (top.size < topK) top.push({ index: i, ...r });
      else if (r.total > top.peek().total) { top.pop(); top.push({ index: i, ...r }); }
      continue;
    }
    for (const childKey of block.children) {
      const child = pyramid[level - 1].get(childKey);
      if (!child) continue;
      if (level - 1 === 0) {
        // Full-resolution cells inherit the parent bound: bounding them
        // would mean scoring them, which is the expensive step.
        queue.push({ negBound, tie: tie++, level: 0, key: childKey });
        continue;
      }
      const bound = blockBound(child, target, weights, criteria, hardFilters);
      stats.blocksBounded++;
      if (bound < 0 || (c != null && bound < c)) { stats.blocksPruned++; continue; }
      queue.push({ negBound: -bound, tie: tie++, level: level - 1, key: childKey });
    }
  }
  stats.cellsSkipped = cells.length - stats.cellsScored;
  const result = [];
  while (top.size) result.push(top.pop());
  result.reverse();
  return { top: result, stats };
}

/** Brute-force search for verification. Scores every cell. */
export function bruteForce(cells, target, weights, criteria, opts = {}) {
  const { topK = DEFAULTS.topK, hardFilters = DEFAULTS.hardFilters } = opts;
  const K = criteria.length;
  const scored = [];
  let evals = 0;
  for (let i = 0; i < cells.length; i++) {
    const v = cells[i].values;
    const scores = {};
    let num = 0, den = 0, filtered = false;
    for (let k = 0; k < K; k++) {
      const id = criteria[k].id;
      const s = similarity(criteria[k].rule, v[id], target[id]);
      if (s != null && weights[k] > 0) evals++;
      scores[id] = s;
      const need = hardFilters[id];
      if (need != null && (s == null || s < need)) { filtered = true; break; }
      if (s != null && weights[k] > 0) { num += weights[k] * s; den += weights[k]; }
    }
    if (filtered) continue;
    // Required criteria with no data: skip (same as staged scorer).
    let ok = true;
    for (const id of Object.keys(hardFilters)) if (v[id] == null || target[id] == null) { ok = false; break; }
    if (!ok) continue;
    scored.push({ index: i, total: den ? num / den : 0, scores });
  }
  scored.sort((a, b) => b.total - a.total);
  return { top: scored.slice(0, topK), evals };
}

// ---------- high-level convenience wrapper ----------
/**
 * One-shot search: compute frozen weights from a sample, build the pyramid,
 * run the pruned search, and return the top-K as UI-shaped locations.
 *
 *   cells:      [{ id?, name?, lat, lon, values: { <criterionId>: number } }]
 *   target:     { <criterionId>: number }   (Mars profile at the chosen point)
 *   importance: number[] in criteria order  (user sliders, same as UI)
 *   criteria:   [{ id, rule }]              (js/criteria.js CRITERIA, in order)
 *   opts: { step, sampleSize, randomSeed, pyramidLevels, topK,
 *           hardFilters, criterionCost, pyramid?, weights?, spread? }
 *
 * Returns { top, weights, spread, means, pyramid, stats } where `top` is
 * [{ ...cell, total, scores }] sorted desc, suitable for the UI.
 */
export function runSearch(cells, target, importance, criteria, opts = {}) {
  const t0 = typeof performance !== "undefined" ? performance.now() : Date.now();
  const step = opts.step ?? 2.5;
  // Weights frozen from a sample unless the caller passed them in.
  let weights = opts.weights, spread = opts.spread, means;
  let sampleEvals = 0, sampleSize = 0;
  if (!weights) {
    const fw = frozenWeights(cells, target, importance, criteria, opts);
    weights = fw.weights; spread = fw.spread; means = fw.means;
    sampleEvals = fw.criterionEvals; sampleSize = fw.sampleSize;
  }
  const pyramid = opts.pyramid ?? buildPyramid(cells, step, criteria, opts.pyramidLevels ?? DEFAULTS.pyramidLevels);
  const { top, stats } = search(cells, pyramid, target, weights, criteria, opts);
  const t1 = typeof performance !== "undefined" ? performance.now() : Date.now();
  // Shape the top-K to match the UI's scored-location contract.
  const topLocs = top.map((r) => ({ ...cells[r.index], total: r.total, scores: r.scores }));
  return {
    top: topLocs, weights, spread, means, pyramid,
    stats: { ...stats, sampleSize, sampleEvals, elapsedMs: t1 - t0,
             totalEvals: stats.criterionEvals + sampleEvals },
  };
}
