// Shared by both globes: the score color ramp, the land mask, and the smooth
// "Color" map, which interpolates grid scores into a continuous equirectangular
// image so the map reads as a field instead of separate cells.

// Low → high score ramp: deep blue → light blue → sand → orange.
export const RAMP = ["#123a82", "#2a63c4", "#7fa6d9", "#e8c9a0", "#f39a42", "#ff7a00"];

const hexToRgb = (hex) => {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};
const RAMP_RGB = RAMP.map(hexToRgb);

/** Interpolated color along RAMP for t in [0, 1]. */
export function rampColor(t) {
  const x = Math.max(0, Math.min(1, t)) * (RAMP.length - 1);
  const i = Math.min(RAMP.length - 2, Math.floor(x));
  const f = x - i;
  const a = RAMP_RGB[i], b = RAMP_RGB[i + 1];
  return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
}

/**
 * Fill land rings (flat [lon, lat, lon, lat, ...] arrays) onto an
 * equirectangular 2D context. Rings that cross the antimeridian are unwrapped,
 * and a ring that wraps the whole globe (Antarctica) is closed through the pole.
 */
export function fillLand(g, rings, width, height) {
  const X = (lon) => (lon + 180) / 360 * width, Y = (lat) => (90 - lat) / 180 * height;
  g.beginPath();
  for (const ring of rings) {
    const pts = [];
    let prev = null, shift = 0;
    for (let k = 0; k < ring.length; k += 2) {
      let lon = ring[k];
      if (prev !== null) {
        if (lon + shift - prev > 180) shift -= 360;
        else if (lon + shift - prev < -180) shift += 360;
      }
      lon += shift; prev = lon;
      pts.push([lon, ring[k + 1]]);
    }
    const span = pts[pts.length - 1][0] - pts[0][0];
    if (Math.abs(span) > 180) {
      const pole = pts.reduce((s, p) => s + p[1], 0) < 0 ? -90 : 90;
      pts.push([pts[pts.length - 1][0], pole], [pts[0][0], pole]);
    }
    for (const off of [-360, 0, 360]) {
      pts.forEach(([lon, lat], i) => (i ? g.lineTo(X(lon + off), Y(lat)) : g.moveTo(X(lon + off), Y(lat))));
      g.closePath();
    }
  }
  g.fill("evenodd");
}

/** Land coverage (0-255 per pixel, anti-aliased) of an equirectangular image; cached per size. */
const maskCache = new WeakMap();
function landMask(rings, width, height) {
  const key = `${width}x${height}`;
  const cached = maskCache.get(rings)?.[key];
  if (cached) return cached;
  const c = document.createElement("canvas");
  c.width = width; c.height = height;
  const g = c.getContext("2d");
  g.fillStyle = "#fff";
  fillLand(g, rings, width, height);
  const d = g.getImageData(0, 0, width, height).data;
  const m = new Uint8Array(width * height);
  for (let i = 0; i < m.length; i++) m[i] = d[i * 4 + 3];
  maskCache.set(rings, { ...maskCache.get(rings), [key]: m });
  return m;
}

/** Lookup from grid cell to grid point, for hover and click on the color map. */
export function cellIndex(points, step) {
  const nx = Math.round(360 / step);
  const map = new Map();
  for (const p of points) {
    if (p.kind === "site") continue;
    const ix = Math.floor((p.lon + 180) / step), iy = Math.floor((90 - p.lat) / step);
    map.set(iy * nx + ix, p);
  }
  return (lat, lon) => {
    const ix = Math.floor((((lon + 180) % 360 + 360) % 360) / step), iy = Math.floor((90 - lat) / step);
    return map.get(iy * nx + ix) || null;
  };
}

/**
 * Smooth score field as an RGBA image (transparent over the ocean).
 *
 * Grid scores go onto a coarse lon/lat grid. Empty cells next to scored ones
 * are filled from their neighbours so coasts and islands are covered, a
 * Gaussian-like 3×3 pass softens the grid, and each output pixel is then a
 * bilinear blend of the four surrounding cell centres, masked to land.
 *
 * @param {Array<{p, t}>} bars  grid points with a normalised score t in [0, 1]
 * @param {number} step         grid spacing in degrees
 * @param {Array} coastlines    land rings; without them the field covers scored cells only
 * @returns {{ canvas: HTMLCanvasElement, data: Uint8ClampedArray, w: number, h: number }}
 */
export function scoreField(bars, step, coastlines, { width = 1024, height = 512, alpha = 0.94 } = {}) {
  const nx = Math.round(360 / step), ny = Math.round(180 / step);
  let v = new Float32Array(nx * ny).fill(NaN);
  for (const { p, t } of bars) {
    if (p.kind === "site") continue;
    const ix = Math.floor((p.lon + 180) / step), iy = Math.floor((90 - p.lat) / step);
    if (ix >= 0 && ix < nx && iy >= 0 && iy < ny) v[iy * nx + ix] = t;
  }
  const at = (a, ix, iy) => a[Math.max(0, Math.min(ny - 1, iy)) * nx + ((ix % nx) + nx) % nx];

  // Grow two cells into empty neighbours (coasts and small islands without grid points).
  for (let pass = 0; pass < 2; pass++) {
    const next = v.slice();
    for (let iy = 0; iy < ny; iy++) for (let ix = 0; ix < nx; ix++) {
      if (!Number.isNaN(v[iy * nx + ix])) continue;
      let s = 0, n = 0;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const q = at(v, ix + dx, iy + dy);
        if (!Number.isNaN(q)) { s += q; n++; }
      }
      if (n) next[iy * nx + ix] = s / n;
    }
    v = next;
  }

  // Light blur (1-2-1 kernel) that ignores empty cells.
  const soft = new Float32Array(nx * ny).fill(NaN);
  for (let iy = 0; iy < ny; iy++) for (let ix = 0; ix < nx; ix++) {
    if (Number.isNaN(v[iy * nx + ix])) continue;
    let s = 0, wsum = 0;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const q = at(v, ix + dx, iy + dy);
      if (Number.isNaN(q)) continue;
      const w = (dx ? 1 : 2) * (dy ? 1 : 2);
      s += q * w; wsum += w;
    }
    soft[iy * nx + ix] = s / wsum;
  }

  const mask = coastlines ? landMask(coastlines, width, height) : null;
  const canvas = document.createElement("canvas");
  canvas.width = width; canvas.height = height;
  const g = canvas.getContext("2d");
  const img = g.createImageData(width, height);
  const d = img.data;
  const A = 255 * alpha;
  for (let y = 0; y < height; y++) {
    const fy = (y + 0.5) / height * ny - 0.5;
    const y0 = Math.floor(fy), wy = fy - y0;
    for (let x = 0; x < width; x++) {
      const i = y * width + x;
      const m = mask ? mask[i] : 255;
      if (!m) continue;
      const fx = (x + 0.5) / width * nx - 0.5;
      const x0 = Math.floor(fx), wx = fx - x0;
      // Bilinear over the four cell centres, renormalised over the ones that have a value.
      let s = 0, wsum = 0;
      const add = (q, w) => { if (!Number.isNaN(q) && w > 0) { s += q * w; wsum += w; } };
      add(at(soft, x0, y0), (1 - wx) * (1 - wy));
      add(at(soft, x0 + 1, y0), wx * (1 - wy));
      add(at(soft, x0, y0 + 1), (1 - wx) * wy);
      add(at(soft, x0 + 1, y0 + 1), wx * wy);
      if (wsum < 0.05) continue;
      const [r, gg, b] = rampColor(s / wsum);
      const o = i * 4;
      d[o] = r; d[o + 1] = gg; d[o + 2] = b;
      // Fade out where only a sliver of a scored cell reaches (no hard rectangle edges).
      d[o + 3] = A * (m / 255) * Math.min(1, wsum * 2.5);
    }
  }
  g.putImageData(img, 0, 0);
  return { canvas, data: d, w: width, h: height };
}
