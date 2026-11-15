// Scoring engine: a JS port of site_weights.py, applied to Earth analog search.
//
//   s_ik    = 1 - |e_ik - m_k|                       similarity of location i to the Mars target on criterion k
//   s̄_k     = (1/N) Σ_i s_ik                         mean similarity of criterion k
//   v_k     = sqrt[(1/N) Σ_i (s_ik - s̄_k)^2]         discriminating power (population std)
//   w_k     = f_k·v_k / Σ_j f_j·v_j                  normalized weight (f_k = user importance slider)
//   total_i = Σ_k w_k·s_ik                           overall similarity, 0-1

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

export function criterionMeans(S, K) {
  const N = S.length;
  const m = new Array(K).fill(0);
  for (const s of S) for (let k = 0; k < K; k++) m[k] += s[k];
  return m.map((x) => x / N);
}

export function criterionSpread(S, means) {
  const N = S.length;
  const v = new Array(means.length).fill(0);
  for (const s of S) for (let k = 0; k < means.length; k++) v[k] += (s[k] - means[k]) ** 2;
  return v.map((x) => Math.sqrt(x / N));
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
 * @param {number[]} importance  slider values in criteriaIds order
 */
export function scoreLocations(locations, target, importance, criteriaIds) {
  const K = criteriaIds.length;
  const S = locations.map((loc) => criteriaIds.map((k) => 1 - Math.abs(loc.values[k] - target[k])));
  const means = criterionMeans(S, K);
  const spread = criterionSpread(S, means);
  const weights = missionWeights(importance, spread);
  const scored = locations.map((loc, i) => {
    const scores = Object.fromEntries(criteriaIds.map((k, j) => [k, S[i][j]]));
    const total = S[i].reduce((acc, s, j) => acc + weights[j] * s, 0);
    return { ...loc, scores, total };
  });
  return { scored, means, spread, weights };
}

export function topN(scored, n = 5) {
  return [...scored].sort((a, b) => b.total - a.total).slice(0, n);
}
