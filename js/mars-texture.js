// Procedural Mars surface texture shared by the Cesium and offline canvas globes.

/** Procedural equirectangular Mars texture (canvas) used as a fallback / base layer. */
export function marsTextureCanvas(width = 1024, height = 512) {
  const canvas = document.createElement("canvas");
  canvas.width = width; canvas.height = height;
  const ctx = canvas.getContext("2d");
  const img = ctx.createImageData(width, height);

  const hash = (x, y, z) => {
    let h = (x * 374761393 + y * 668265263 + z * 1442695041) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
  };
  const noise = (x, y, z) => {
    const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
    const u = x - xi, v = y - yi, w = z - zi;
    const s = (t) => t * t * (3 - 2 * t);
    const su = s(u), sv = s(v), sw = s(w);
    const n = (a, b, c) => hash(xi + a, yi + b, zi + c);
    const l = (a, b, t) => a + (b - a) * t;
    return l(l(l(n(0,0,0), n(1,0,0), su), l(n(0,1,0), n(1,1,0), su), sv),
             l(l(n(0,0,1), n(1,0,1), su), l(n(0,1,1), n(1,1,1), su), sv), sw);
  };
  const fbm = (x, y, z, oct = 5) => {
    let a = 0.5, f = 1, t = 0, nrm = 0;
    for (let o = 0; o < oct; o++) { t += a * noise(x * f + o * 17, y * f, z * f); nrm += a; a *= 0.5; f *= 2.03; }
    return t / nrm;
  };
  // Broad albedo features (lat, lon, radius°, strength: + bright / - dark)
  const FEATURES = [
    [10, 70, 16, -0.55],  // Syrtis Major
    [45, -30, 22, -0.45], // Acidalia
    [-25, -40, 25, -0.35],// Mare Erythraeum
    [-20, 130, 20, -0.30],// Mare Cimmerium
    [-15, 20, 18, -0.35], // Sinus Meridiani / Sabaeus
    [5, -110, 30, 0.35],  // Tharsis
    [20, 20, 25, 0.30],   // Arabia Terra
    [-42, 70, 14, 0.45],  // Hellas
    [25, 150, 18, 0.25],  // Elysium
    [-50, -40, 10, 0.25], // Argyre
  ];
  const DEG = Math.PI / 180;
  const D0 = [124, 52, 30], D1 = [186, 92, 52], D2 = [222, 140, 88], D3 = [238, 178, 124];
  const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

  for (let py = 0; py < height; py++) {
    const lat = 90 - (py + 0.5) * (180 / height);
    const la = lat * DEG, cl = Math.cos(la), sl = Math.sin(la);
    for (let px = 0; px < width; px++) {
      const lon = -180 + (px + 0.5) * (360 / width);
      const lo = lon * DEG;
      const x = cl * Math.cos(lo), y = cl * Math.sin(lo), z = sl;
      let v = fbm(x * 2.2 + 5, y * 2.2 + 5, z * 2.2 + 5);
      v += 0.22 * (fbm(x * 9 + 1, y * 9 + 1, z * 9 + 1, 3) - 0.5);
      for (const [fl, fo, r, s] of FEATURES) {
        const d = Math.acos(Math.min(1, Math.sin(fl * DEG) * sl + Math.cos(fl * DEG) * cl * Math.cos(lo - fo * DEG))) / DEG;
        v += s * Math.exp(-((d / r) ** 2)) * (0.6 + 0.4 * noise(x * 6, y * 6, z * 6));
      }
      // Valles Marineris
      if (lat > -14 && lat < -3 && lon > -95 && lon < -40) v -= 0.25 * Math.exp(-(((lat + 8) / 3) ** 2));
      v = Math.max(0, Math.min(1, v));
      let c = v < 0.33 ? mix(D0, D1, v / 0.33) : v < 0.66 ? mix(D1, D2, (v - 0.33) / 0.33) : mix(D2, D3, (v - 0.66) / 0.34);
      // Polar caps with ragged edges
      const capEdge = (lat > 0 ? 79 : -82) + (noise(x * 14, y * 14, z * 14) - 0.5) * 5;
      const cap = lat > 0 ? lat - capEdge : capEdge - lat;
      if (cap > 0) c = mix(c, [246, 240, 236], Math.min(1, cap / 3));
      const i = (py * width + px) * 4;
      img.data[i] = c[0]; img.data[i + 1] = c[1]; img.data[i + 2] = c[2]; img.data[i + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  // Scattered craters: low-contrast floors and sun-lit rims, as in orbital mosaics.
  let seed = 7;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  for (let k = 0; k < 420; k++) {
    const cx = rnd() * width, cy = height * (0.12 + rnd() * 0.76), r = 1 + rnd() ** 3 * 9;
    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2);
    ctx.fillStyle = "rgba(70,25,12,0.13)"; ctx.fill();
    ctx.beginPath(); ctx.arc(cx - r * 0.25, cy - r * 0.25, r * 0.75, 0, Math.PI * 2);
    ctx.strokeStyle = "rgba(255,210,170,0.08)"; ctx.lineWidth = Math.max(0.6, r * 0.25); ctx.stroke();
  }
  return canvas;
}
