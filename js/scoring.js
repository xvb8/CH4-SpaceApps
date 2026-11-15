// Scoring engine: a JS port of site_weights.py, applied to Earth analog search,
// with the per-criterion similarity rules from the project's Criteria settings.
//
//   s_ik    = rule_k(e_ik, m_k)                       similarity of location i to the Mars target on criterion k
//             ratio     min ÷ max; if either value is 0: 1 ÷ (1 + |e − m|)
//             logRatio  ratio of log-scaled values (for sizes spanning orders of magnitude)
//             gap       1 ÷ (1 + |e − m| ÷ scale)
//             fraction  1 − |e − m|
//             match     1 if both are present / absent (value ≥ threshold), else 0
//   s̄_k     = (1/N) Σ_i s_ik                         mean similarity of criterion k
//   v_k     = sqrt[(1/N) Σ_i (s_ik - s̄_k)^2]         discriminating power (population std)
//   w_k     = f_k·v_k / Σ_j f_j·v_j                  normalized weight (f_k = user importance slider)
//   total_i = Σ_k w_k·s_ik / Σ_k w_k                 weighted average (Gower) over the criteria with data
//
// Missing values (null / undefined) are skipped for that pair, never scored as 0.

const DEG = Math.PI / 180;

/** Great-circle angular distance in radians. */
export function angularDistance(lat1, lon1, lat2, lon2) {
  const a =
    Math.sin(((lat2 - lat1) * DEG) / 2) ** 2 +
    Math.cos(lat1 * DEG) * Math.cos(lat2 * DEG) * Math.sin(((lon2 - lon1) * DEG) / 2) ** 2;
  return 2 * Math.asin(Math.min(1, Math.sqrt(a)));
}

/**
 * Estimate the criterion profile at a Mars coordinate by inverse-distance
 * weighting the nearest anchor regions.
 */
export function marsProfileAt(lat, lon, regions, criteriaIds, nearest = 4) {
  const ranked = regions
    .map((r) => ({ r, d: angularDistance(lat, lon, r.lat, r.lon) }))
    .sort((a, b) => a.d - b.d)
    .slice(0, nearest);
  if (ranked[0].d < 1e-4) return { values: { ...ranked[0].r.values }, neighbors: ranked };
  const w = ranked.map(({ d }) => 1 / d ** 2);
  const wsum = w.reduce((a, b) => a + b, 0);
  const values = {};
  for (const k of criteriaIds) {
    values[k] = ranked.reduce((acc, { r }, i) => acc + w[i] * r.values[k], 0) / wsum;
  }
  return { values, neighbors: ranked };
}

const ratio = (e, m) => (e === 0 || m === 0 ? 1 / (1 + Math.abs(e - m)) : Math.min(e, m) / Math.max(e, m));
// Maps [0, 1] onto [0, 1] logarithmically, so a 10× size difference counts as one step.
const logScale = (x) => Math.log10(1 + 9 * x);

/** Similarity (0-1) of an Earth value to a Mars value under one criterion's rule; null if either is missing. */
export function similarity(rule, e, m) {
  if (e == null || m == null || Number.isNaN(e) || Number.isNaN(m)) return null;
  switch (rule.type) {
    case "ratio": return ratio(Math.abs(e), Math.abs(m));
    case "logRatio": return ratio(logScale(Math.abs(e)), logScale(Math.abs(m)));
    case "gap": return 1 / (1 + Math.abs(e - m) / rule.scale);
    case "fraction": return Math.max(0, 1 - Math.abs(e - m));
    case "match": return (e >= rule.threshold) === (m >= rule.threshold) ? 1 : 0;
    default: throw new Error(`Unknown scoring rule: ${rule.type}`);
  }
}

export function criterionMeans(S, K) {
  const sum = new Array(K).fill(0), n = new Array(K).fill(0);
  for (const s of S) for (let k = 0; k < K; k++) if (s[k] != null) { sum[k] += s[k]; n[k]++; }
  return sum.map((x, k) => (n[k] ? x / n[k] : 0));
}

export function criterionSpread(S, means) {
  const K = means.length;
  const sum = new Array(K).fill(0), n = new Array(K).fill(0);
  for (const s of S) for (let k = 0; k < K; k++) if (s[k] != null) { sum[k] += (s[k] - means[k]) ** 2; n[k]++; }
  return sum.map((x, k) => (n[k] ? Math.sqrt(x / n[k]) : 0));
}

export function missionWeights(fidelity, spread) {
  const products = fidelity.map((f, k) => f * spread[k]);
  const total = products.reduce((a, b) => a + b, 0);
  if (total === 0) {
    // Every weighted criterion has zero spread: fall back to plain importance weights.
    const fsum = fidelity.reduce((a, b) => a + b, 0);
    if (fsum === 0) throw new Error("All importance values are zero; weights are undefined.");
    return fidelity.map((f) => f / fsum);
  }
  return products.map((p) => p / total);
}

/**
 * Score every location against the Mars target.
 * @param {Array<{values: Object}>} locations  named sites and grid points
 * @param {Object} target   criterion -> Mars value
 * @param {number[]} importance  slider values in criteria order
 * @param {Array<{id: string, rule: Object}>} criteria  criterion definitions (js/criteria.js)
 */
export function scoreLocations(locations, target, importance, criteria) {
  const K = criteria.length;
  const S = locations.map((loc) => criteria.map((c) => similarity(c.rule, loc.values[c.id], target[c.id])));
  const means = criterionMeans(S, K);
  const spread = criterionSpread(S, means);
  const weights = missionWeights(importance, spread);
  const scored = locations.map((loc, i) => {
    const scores = Object.fromEntries(criteria.map((c, j) => [c.id, S[i][j]]));
    let num = 0, den = 0;
    S[i].forEach((s, j) => { if (s != null) { num += weights[j] * s; den += weights[j]; } });
    return { ...loc, scores, total: den ? num / den : 0 };
  });
  return { scored, means, spread, weights };
}

export function topN(scored, n = 5) {
  return [...scored].sort((a, b) => b.total - a.total).slice(0, n);
}
