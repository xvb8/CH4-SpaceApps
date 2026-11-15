// Static, photographic-looking star field: a power-law brightness distribution
// (many faint stars, few bright ones), realistic color temperatures and a faint
// Milky Way band. The sky is rendered once to an offscreen layer; every few
// seconds a handful of stars scintillate briefly. No parallax, no meteors.

// Star colors by temperature, from hot blue-white to cool orange (low saturation).
const COLORS = [
  [196, 214, 255], [214, 226, 255], [236, 241, 255], [255, 255, 255], [255, 255, 255],
  [255, 250, 240], [255, 242, 222], [255, 228, 196], [255, 210, 168],
];
const COLOR_WEIGHTS = [0.04, 0.09, 0.16, 0.22, 0.2, 0.12, 0.09, 0.06, 0.02];

function rng(seed) {
  return () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
}
function pick(r, weights) {
  let x = r();
  for (let i = 0; i < weights.length; i++) { x -= weights[i]; if (x <= 0) return i; }
  return weights.length - 1;
}
function gauss(r) {
  return Math.sqrt(-2 * Math.log(r() || 1e-9)) * Math.cos(2 * Math.PI * r());
}

export function startStarfield(canvas) {
  const ctx = canvas.getContext("2d");
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const layer = document.createElement("canvas");
  const lctx = layer.getContext("2d");
  let w = 0, h = 0, dpr = 1, stars = [], twinkling = [], raf = 0, timer = 0;

  function star(r, x, y, faint = false) {
    const u = r();
    // Power-law brightness: most stars sit near the detection limit.
    const mag = faint ? u ** 1.5 * 0.35 : u ** 3.2;
    return {
      x, y,
      a: faint ? 0.08 + mag * 0.5 : 0.18 + mag * 0.82,
      s: faint ? 0.35 + mag * 0.4 : 0.4 + mag ** 1.6 * 1.25,
      c: COLORS[pick(r, COLOR_WEIGHTS)],
      faint,
      bright: !faint && mag > 0.55,
    };
  }

  function paintStar(g, st, alpha = st.a, scale = 1) {
    const [cr, cg, cb] = st.c;
    const s = st.s * scale;
    if (st.bright) {
      // Faint point-spread halo, as on a long exposure.
      const halo = g.createRadialGradient(st.x, st.y, 0, st.x, st.y, s * 3.2);
      halo.addColorStop(0, `rgba(${cr},${cg},${cb},${alpha * 0.22})`);
      halo.addColorStop(1, `rgba(${cr},${cg},${cb},0)`);
      g.fillStyle = halo;
      g.fillRect(st.x - s * 3.2, st.y - s * 3.2, s * 6.4, s * 6.4);
    }
    g.fillStyle = `rgba(${cr},${cg},${cb},${alpha})`;
    g.beginPath();
    g.arc(st.x, st.y, s, 0, Math.PI * 2);
    g.fill();
  }

  function build() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    w = window.innerWidth; h = window.innerHeight;
    for (const c of [canvas, layer]) { c.width = Math.round(w * dpr); c.height = Math.round(h * dpr); }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    lctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    lctx.clearRect(0, 0, w, h);

    const r = rng(20251004);
    // Milky Way band: a diagonal across the viewport.
    const ax = -0.1 * w, ay = 0.82 * h, bx = 1.1 * w, by = 0.12 * h;
    const len = Math.hypot(bx - ax, by - ay), nx = -(by - ay) / len, ny = (bx - ax) / len;
    const band = Math.min(w, h) * 0.16;

    // Diffuse glow of unresolved stars, kept very faint.
    for (let i = 0; i <= 14; i++) {
      const t = i / 14, cx = ax + (bx - ax) * t, cy = ay + (by - ay) * t;
      const rad = band * (1.6 + 0.8 * Math.sin(i * 1.7));
      const g = lctx.createRadialGradient(cx, cy, 0, cx, cy, rad);
      g.addColorStop(0, "rgba(150, 160, 190, 0.035)");
      g.addColorStop(1, "rgba(150, 160, 190, 0)");
      lctx.fillStyle = g;
      lctx.fillRect(cx - rad, cy - rad, rad * 2, rad * 2);
    }

    stars = [];
    const area = w * h;
    const count = Math.round(area / 2000);            // ~30% denser than before
    for (let i = 0; i < count; i++) stars.push(star(r, r() * w, r() * h));
    // Dense faint population concentrated in the band.
    const bandCount = Math.round(area / 900);
    for (let i = 0; i < bandCount; i++) {
      const t = r(), off = gauss(r) * band * 0.55;
      stars.push(star(r, ax + (bx - ax) * t + nx * off, ay + (by - ay) * t + ny * off, true));
    }
    for (const st of stars) paintStar(lctx, st);
    ctx.clearRect(0, 0, w, h);
    ctx.drawImage(layer, 0, 0, w, h);
  }

  // Occasional scintillation of a few brighter stars.
  const candidates = () => stars.filter((s) => !s.faint && s.a > 0.45);
  function scheduleTwinkle() {
    if (reduced) return;
    clearTimeout(timer);
    timer = setTimeout(() => {
      const pool = candidates();
      const n = 1 + Math.floor(Math.random() * 2);
      const now = performance.now();
      for (let i = 0; i < n && pool.length; i++) {
        twinkling.push({ st: pool[(Math.random() * pool.length) | 0], t0: now, dur: 600 + Math.random() * 700 });
      }
      if (!raf && !document.hidden) raf = requestAnimationFrame(frame);
      scheduleTwinkle();
    }, 2500 + Math.random() * 4500);
  }

  function frame(now) {
    raf = 0;
    ctx.clearRect(0, 0, w, h);
    ctx.drawImage(layer, 0, 0, w, h);
    twinkling = twinkling.filter((tw) => now - tw.t0 < tw.dur);
    for (const tw of twinkling) {
      const p = (now - tw.t0) / tw.dur;
      // Irregular flicker under a smooth envelope.
      const env = Math.sin(Math.PI * p);
      const flick = 0.6 + 0.4 * Math.sin(p * 38 + tw.t0);
      paintStar(ctx, tw.st, Math.min(1, tw.st.a + 0.5 * env * flick), 1 + 0.35 * env);
    }
    if (twinkling.length && !document.hidden) raf = requestAnimationFrame(frame);
  }

  let resizeTimer = 0;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(build, 150);
  });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) clearTimeout(timer); else scheduleTwinkle();
  });

  build();
  scheduleTwinkle();
}
