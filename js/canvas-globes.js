// Offline globes for sandboxed / no-network builds (see tools/build_snowflake.mjs).
// Same API as globes.js, rendered with a 2D canvas orthographic projection:
// a textured Mars target picker and an Earth score map with radial score spikes.

import { marsTextureCanvas } from "./mars-texture.js";

const DEG = Math.PI / 180;
const BAR_MAX = 0.22;       // spike length at the top score, in planet radii
const BAR_MIN = 0.005;
const MARKER_ALT = BAR_MAX + 0.03;

// Low → high score color ramp (deep violet → magenta → coral → cream).
export const RAMP = ["#2b0f54", "#6a1c8f", "#b6307b", "#f0506e", "#fc9f6c", "#fcf3c8"];

export function cesiumAvailable() {
  return true;
}

export function initIon() {}

/** Interpolated color along RAMP for t in [0, 1]. */
export function rampColor(t) {
  const x = Math.max(0, Math.min(1, t)) * (RAMP.length - 1);
  const i = Math.min(RAMP.length - 2, Math.floor(x));
  const f = x - i;
  const a = hexToRgb(RAMP[i]), b = hexToRgb(RAMP[i + 1]);
  return [0, 1, 2].map((j) => a[j] + (b[j] - a[j]) * f);
}
function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

// Canvas fonts follow the page's CSS font stacks (read once; they never change).
const fontStacks = {};
const fontOf = (weight, px, display = true) => {
  const key = display ? "--font-display" : "--font-body";
  if (!(key in fontStacks)) fontStacks[key] = getComputedStyle(document.documentElement).getPropertyValue(key).trim() || "system-ui, sans-serif";
  return `${weight} ${px}px ${fontStacks[key]}`;
};
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);
const wrapLon = (l) => ((((l + 180) % 360) + 360) % 360) - 180;

/**
 * Orthographic globe on a canvas: drag to rotate, wheel / pinch to zoom,
 * click to pick, idle auto-rotation, renders only while visible.
 */
class Globe {
  constructor(el, { label = "Globe", texture = null, ocean = null, rim = "rgba(255,170,130,.35)", rotateSpeed = 4, center = [15, 0], zoom = 1, minZoom = 0.7, maxZoom = 6 }) {
    this.el = el;
    this.canvas = document.createElement("canvas");
    this.canvas.setAttribute("role", "img");
    this.canvas.setAttribute("aria-label", label);
    this.canvas.style.touchAction = "none";
    this.canvas.style.cursor = "grab";
    el.appendChild(this.canvas);
    this.ctx = this.canvas.getContext("2d");
    this.texture = texture;   // { data, w, h } equirectangular RGBA
    this.ocean = ocean;
    this.rim = rim;
    this.lat0 = center[0]; this.lon0 = center[1];
    this.zoom = zoom; this.minZoom = minZoom; this.maxZoom = maxZoom;
    this.rotateSpeed = rotateSpeed;   // degrees / second
    this.lastInput = -Infinity;
    this.anim = null;
    this.visible = true;
    this.dirty = true;
    this.overlays = [];   // (ctx, globe, now) => boolean (true = keeps animating)
    this.onPick = null;
    this.onHover = null;
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.buf = null;
    this._loop = this._loop.bind(this);

    this._bindInput();
    this._resize();
    if ("ResizeObserver" in window) new ResizeObserver(() => this._resize()).observe(el);
    else window.addEventListener("resize", () => this._resize());
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(([e]) => { this.visible = e.isIntersecting; if (this.visible) this._kick(); }, { rootMargin: "120px" }).observe(el);
    }
    document.addEventListener("visibilitychange", () => { if (!document.hidden) this._kick(); });
    this._kick();
  }

  get radius() { return Math.min(this.w, this.h) * 0.42 * this.zoom; }

  _resize() {
    const r = this.el.getBoundingClientRect();
    this.w = Math.max(1, r.width); this.h = Math.max(1, r.height);
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = Math.round(this.w * this.dpr);
    this.canvas.height = Math.round(this.h * this.dpr);
    this.canvas.style.width = `${this.w}px`;
    this.canvas.style.height = `${this.h}px`;
    // Low-res buffer for the textured surface; scaled up with smoothing.
    const k = Math.min(1, 520 / Math.max(this.w, this.h));
    const bw = Math.max(1, Math.round(this.w * k)), bh = Math.max(1, Math.round(this.h * k));
    this.bufCanvas = document.createElement("canvas");
    this.bufCanvas.width = bw; this.bufCanvas.height = bh;
    this.bufCtx = this.bufCanvas.getContext("2d");
    this.buf = this.bufCtx.createImageData(bw, bh);
    this.surfaceKey = null;
    this.dirty = true;
    this._kick();
  }

  _basis() {
    const p = this.lat0 * DEG, l = this.lon0 * DEG;
    const cp = Math.cos(p), sp = Math.sin(p), cl = Math.cos(l), sl = Math.sin(l);
    return { f: [cp * cl, cp * sl, sp], e: [-sl, cl, 0], n: [-sp * cl, -sp * sl, cp] };
  }

  /** lat/lon (+ altitude in radii) → screen {x, y, z}; z > 0 is the near side. */
  project(lat, lon, alt = 0, B = this._basis()) {
    const p = lat * DEG, l = lon * DEG, r = 1 + alt;
    const X = Math.cos(p) * Math.cos(l) * r, Y = Math.cos(p) * Math.sin(l) * r, Z = Math.sin(p) * r;
    const u = X * B.e[0] + Y * B.e[1] + Z * B.e[2];
    const v = X * B.n[0] + Y * B.n[1] + Z * B.n[2];
    const z = X * B.f[0] + Y * B.f[1] + Z * B.f[2];
    const R = this.radius;
    return { x: this.w / 2 + u * R, y: this.h / 2 - v * R, z };
  }

  /** Screen point → { lat, lon } or null when off the globe. */
  unproject(x, y) {
    const R = this.radius;
    const u = (x - this.w / 2) / R, v = -(y - this.h / 2) / R;
    const d = u * u + v * v;
    if (d > 1) return null;
    const w = Math.sqrt(1 - d), B = this._basis();
    const X = u * B.e[0] + v * B.n[0] + w * B.f[0];
    const Y = u * B.e[1] + v * B.n[1] + w * B.f[1];
    const Z = u * B.e[2] + v * B.n[2] + w * B.f[2];
    return { lat: Math.asin(Math.max(-1, Math.min(1, Z))) / DEG, lon: Math.atan2(Y, X) / DEG };
  }

  flyTo(lat, lon, zoom = this.zoom, duration = 1600) {
    this.lastInput = performance.now();
    const from = { lat: this.lat0, lon: this.lon0, zoom: this.zoom };
    let dl = wrapLon(lon - from.lon);
    this.anim = { t0: performance.now(), duration: this.reduced ? 1 : duration, from, to: { lat, lon: from.lon + dl, zoom } };
    this._kick();
  }

  pause() { this.lastInput = performance.now(); }

  _bindInput() {
    const c = this.canvas;
    const pts = new Map();
    let down = null, pinch = null;
    const pos = (e) => { const r = c.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
    c.addEventListener("pointerdown", (e) => {
      c.setPointerCapture(e.pointerId);
      pts.set(e.pointerId, pos(e));
      this.anim = null; this.pause();
      if (pts.size === 1) { down = { ...pos(e), lat: this.lat0, lon: this.lon0, moved: 0 }; c.style.cursor = "grabbing"; }
      if (pts.size === 2) {
        const [a, b] = [...pts.values()];
        pinch = { d: Math.hypot(a.x - b.x, a.y - b.y), zoom: this.zoom };
        down = null;
      }
    });
    c.addEventListener("pointermove", (e) => {
      const p = pos(e);
      if (pts.has(e.pointerId)) pts.set(e.pointerId, p);
      if (pinch && pts.size === 2) {
        const [a, b] = [...pts.values()];
        this._setZoom(pinch.zoom * Math.hypot(a.x - b.x, a.y - b.y) / (pinch.d || 1));
        this.pause();
        return;
      }
      if (down) {
        const dx = p.x - down.x, dy = p.y - down.y;
        down.moved = Math.max(down.moved, Math.hypot(dx, dy));
        const s = 1 / (this.radius * DEG);
        this.lon0 = wrapLon(down.lon - dx * s);
        this.lat0 = Math.max(-85, Math.min(85, down.lat + dy * s));
        this.dirty = true; this.pause(); this._kick();
        this.onHover?.(null);
        return;
      }
      if (e.pointerType === "mouse") this.onHover?.(p);
    });
    const end = (e) => {
      const p = pos(e);
      pts.delete(e.pointerId);
      if (pts.size < 2) pinch = null;
      if (down && down.moved < 5) this.onPick?.(p);
      if (pts.size === 0) { down = null; c.style.cursor = "grab"; }
    };
    c.addEventListener("pointerup", end);
    c.addEventListener("pointercancel", (e) => { pts.delete(e.pointerId); down = null; pinch = null; c.style.cursor = "grab"; });
    c.addEventListener("pointerleave", () => this.onHover?.(null));
    c.addEventListener("wheel", (e) => {
      e.preventDefault();
      this.anim = null; this.pause();
      this._setZoom(this.zoom * Math.exp(-e.deltaY * 0.0015));
    }, { passive: false });
  }

  _setZoom(z) {
    this.zoom = Math.max(this.minZoom, Math.min(this.maxZoom, z));
    this.dirty = true; this._kick();
  }

  _kick() {
    if (this.raf || !this.visible || document.hidden) return;
    this.lastFrame = performance.now();
    this.raf = requestAnimationFrame(this._loop);
  }

  _loop(now) {
    this.raf = 0;
    if (!this.visible || document.hidden) return;
    const dt = Math.max(0, Math.min(0.1, (now - this.lastFrame) / 1000));
    this.lastFrame = now;
    let active = false;
    if (this.anim) {
      // rAF timestamps can precede the performance.now() taken in flyTo, so clamp below too.
      const a = this.anim, t = Math.max(0, Math.min(1, (now - a.t0) / a.duration)), k = easeInOut(t);
      this.lat0 = a.from.lat + (a.to.lat - a.from.lat) * k;
      this.lon0 = wrapLon(a.from.lon + (a.to.lon - a.from.lon) * k);
      this.zoom = a.from.zoom + (a.to.zoom - a.from.zoom) * k;
      if (t >= 1) this.anim = null;
      this.dirty = true; active = true;
      this.lastInput = now;
    } else if (!this.reduced && now - this.lastInput > 9000) {
      this.lon0 = wrapLon(this.lon0 - this.rotateSpeed * dt);   // surface drifts west → east, as in globes.js
      this.dirty = true; active = true;
    } else if (!this.reduced && !this.idleTimer) {
      // Idle after input: wake up when auto-rotation should resume instead of spinning frames.
      this.idleTimer = setTimeout(() => { this.idleTimer = 0; this._kick(); }, 9000 - (now - this.lastInput) + 20);
    }
    if (this.dirty) { this._renderSurface(); this.dirty = false; }
    if (this._draw(now)) active = true;
    if (active) this._kick();
  }

  /** Per-pixel inverse orthographic lookup into the equirectangular texture. */
  _renderSurface() {
    const { buf } = this;
    const bw = buf.width, bh = buf.height, sx = bw / this.w;
    const R = this.radius * sx, cx = bw / 2, cy = bh / 2;
    // An untextured globe looks the same at every rotation: only size changes it.
    const key = `${bw}x${bh}@${R}`;
    if (!this.texture && key === this.surfaceKey) return;
    this.surfaceKey = key;
    const d = buf.data;
    d.fill(0);
    const B = this._basis();
    const tex = this.texture;
    const oc = this.ocean ? hexToRgb(this.ocean) : [20, 30, 70];
    const y0 = Math.max(0, Math.floor(cy - R)), y1 = Math.min(bh, Math.ceil(cy + R));
    const x0 = Math.max(0, Math.floor(cx - R)), x1 = Math.min(bw, Math.ceil(cx + R));
    for (let py = y0; py < y1; py++) {
      const v = -(py + 0.5 - cy) / R;
      for (let px = x0; px < x1; px++) {
        const u = (px + 0.5 - cx) / R;
        const dd = u * u + v * v;
        if (dd > 1) continue;
        const w = Math.sqrt(1 - dd);
        // Soft light from the upper left, plus limb darkening.
        const light = Math.max(0.18, 0.35 + 0.75 * (w * 0.75 - u * 0.35 + v * 0.35));
        const edge = Math.min(1, (1 - Math.sqrt(dd)) * R * 0.9);   // anti-aliased rim
        let r, g, b;
        if (tex) {
          const X = u * B.e[0] + v * B.n[0] + w * B.f[0];
          const Y = u * B.e[1] + v * B.n[1] + w * B.f[1];
          const Z = u * B.e[2] + v * B.n[2] + w * B.f[2];
          const lat = Math.asin(Z), lon = Math.atan2(Y, X);
          const tx = Math.min(tex.w - 1, ((lon / Math.PI + 1) / 2 * tex.w) | 0);
          const ty = Math.min(tex.h - 1, ((0.5 - lat / Math.PI) * tex.h) | 0);
          const ti = (ty * tex.w + tx) * 4;
          r = tex.data[ti]; g = tex.data[ti + 1]; b = tex.data[ti + 2];
        } else {
          [r, g, b] = oc;
        }
        const i = (py * bw + px) * 4;
        d[i] = Math.min(255, r * light); d[i + 1] = Math.min(255, g * light); d[i + 2] = Math.min(255, b * light);
        d[i + 3] = 255 * Math.max(0, edge);
      }
    }
    this.bufCtx.putImageData(buf, 0, 0);
  }

  _draw(now) {
    const { ctx, dpr, w, h } = this;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    const R = this.radius, cx = w / 2, cy = h / 2;
    // Atmosphere glow
    const glow = ctx.createRadialGradient(cx, cy, R * 0.96, cx, cy, R * 1.14);
    glow.addColorStop(0, this.rim);
    glow.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = glow;
    ctx.beginPath(); ctx.arc(cx, cy, R * 1.14, 0, Math.PI * 2); ctx.fill();
    ctx.imageSmoothingEnabled = true;
    ctx.drawImage(this.bufCanvas, 0, 0, w, h);
    this._graticule();
    let animating = false;
    for (const o of this.overlays) if (o(ctx, this, now)) animating = true;
    return animating;
  }

  _graticule() {
    const { ctx } = this, B = this._basis();
    ctx.save();
    ctx.strokeStyle = "rgba(255,255,255,.07)";
    ctx.lineWidth = 1;
    const line = (pts) => {
      ctx.beginPath();
      let pen = false;
      for (const [la, lo] of pts) {
        const p = this.project(la, lo, 0, B);
        if (p.z < 0) { pen = false; continue; }
        if (pen) ctx.lineTo(p.x, p.y); else ctx.moveTo(p.x, p.y);
        pen = true;
      }
      ctx.stroke();
    };
    for (let la = -60; la <= 60; la += 30) line(Array.from({ length: 73 }, (_, i) => [la, -180 + i * 5]));
    for (let lo = -180; lo < 180; lo += 30) line(Array.from({ length: 37 }, (_, i) => [-90 + i * 5, lo]));
    ctx.restore();
  }
}

/** Pill label anchored above (x, y). Pass `placed` to nudge it upward past labels already drawn. */
function labelPill(ctx, text, x, y, { font, fill = "#fff", bg = "rgba(26,11,54,.75)", padX = 9, padY = 5, placed = null }) {
  ctx.font = font;
  const tw = ctx.measureText(text).width, th = parseFloat(font.split(" ")[1]);
  const bw = tw + padX * 2, bh = th + padY * 2;
  if (placed) {
    const hits = (r) => placed.some((q) => r.x < q.x + q.w + 4 && q.x < r.x + r.w + 4 && r.y < q.y + q.h + 3 && q.y < r.y + r.h + 3);
    for (let k = 0; k < 8 && hits({ x: x - bw / 2, y: y - bh, w: bw, h: bh }); k++) y -= bh + 3;
    placed.push({ x: x - bw / 2, y: y - bh, w: bw, h: bh });
  }
  ctx.fillStyle = bg;
  ctx.beginPath();
  if (ctx.roundRect) ctx.roundRect(x - bw / 2, y - bh, bw, bh, bh / 2); else ctx.rect(x - bw / 2, y - bh, bw, bh);
  ctx.fill();
  ctx.fillStyle = fill;
  ctx.textAlign = "center"; ctx.textBaseline = "middle";
  ctx.fillText(text, x, y - bh / 2 + 0.5);
}

// ===================================================================== MARS

/**
 * Create the Mars viewer.
 * @param {HTMLElement} el
 * @param {{ regions: Array, onPick: (lat:number, lon:number) => void, onStatus: (msg:string) => void }} opts
 */
export async function createMarsViewer(el, { regions, onPick, onStatus }) {
  const tc = marsTextureCanvas(1024, 512);
  const texture = { data: tc.getContext("2d").getImageData(0, 0, tc.width, tc.height).data, w: tc.width, h: tc.height };
  const globe = new Globe(el, { label: "Interactive Mars globe: click to set the target, or use the coordinate fields", texture, rim: "rgba(255,170,120,.38)", center: [18, 77], zoom: 1, rotateSpeed: 3 });
  const source = "Procedural Mars · offline";
  onStatus?.(source);

  let target = null;
  globe.overlays.push((ctx, g, now) => {
    const B = g._basis();
    ctx.save();
    for (const r of regions) {
      const p = g.project(r.lat, r.lon, 0, B);
      if (p.z < 0.08) continue;
      ctx.globalAlpha = Math.min(1, p.z * 2.5);
      ctx.beginPath(); ctx.arc(p.x, p.y, 3.5, 0, Math.PI * 2);
      ctx.fillStyle = "rgba(255,242,230,.92)"; ctx.fill();
      ctx.lineWidth = 2; ctx.strokeStyle = "#ff8fb8"; ctx.stroke();
      if (g.zoom > 0.85) {
        ctx.font = fontOf(600, 12, false);
        ctx.textAlign = "center"; ctx.textBaseline = "bottom";
        ctx.lineWidth = 3; ctx.strokeStyle = "rgba(0,0,0,.7)";
        ctx.strokeText(r.name, p.x, p.y - 8);
        ctx.fillStyle = "rgba(255,255,255,.88)";
        ctx.fillText(r.name, p.x, p.y - 8);
      }
    }
    ctx.globalAlpha = 1;
    if (!target) { ctx.restore(); return false; }
    const p = g.project(target.lat, target.lon, 0, B);
    if (p.z > 0) {
      const s = 7 + 2 * Math.sin(now / 260);
      ctx.beginPath(); ctx.arc(p.x, p.y, s + 6, 0, Math.PI * 2);
      ctx.fillStyle = "rgba(255,95,162,.25)"; ctx.fill();
      ctx.beginPath(); ctx.arc(p.x, p.y, s, 0, Math.PI * 2);
      ctx.fillStyle = "#ff5fa2"; ctx.fill();
      ctx.lineWidth = 3; ctx.strokeStyle = "#fff"; ctx.stroke();
      labelPill(ctx, "Target", p.x, p.y - 16, { font: fontOf(700, 14), bg: "rgba(58,11,42,.8)" });
    }
    ctx.restore();
    return p.z > 0 && !g.reduced;   // keep pulsing while visible
  });

  globe.onPick = (pt) => {
    const ll = globe.unproject(pt.x, pt.y);
    if (ll) onPick(ll.lat, ll.lon);
  };

  return {
    viewer: globe,
    source,
    setTarget(lat, lon, fly = true) {
      target = { lat, lon };
      globe.pause();
      if (fly) globe.flyTo(lat, lon, Math.max(globe.zoom, 1.35), 1800);
      else { globe.dirty = true; globe._kick(); }
    },
  };
}

// ==================================================================== EARTH

export async function createEarthViewer(el, { onHover, onPick }) {
  const globe = new Globe(el, { label: "Earth globe of similarity scores for every tested location; the rankings and charts below list the same results", ocean: "#13265e", rim: "rgba(110,160,255,.35)", center: [15, -40], zoom: 1, rotateSpeed: 4 });
  let bars = [];        // { p: location, t: 0-1 }
  let top = [];

  globe.overlays.push((ctx, g) => {
    const B = g._basis();
    ctx.save();
    ctx.lineCap = "round";
    const lw = Math.max(1.6, g.radius / 120);
    const drawn = [];
    for (const b of bars) {
      const base = g.project(b.p.lat, b.p.lon, 0, B);
      if (base.z < 0) continue;
      const tip = g.project(b.p.lat, b.p.lon, BAR_MIN + b.t ** 1.6 * (BAR_MAX - BAR_MIN), B);
      drawn.push({ b, base, tip });
    }
    // Batch spikes into one path per color step: ~1.9k separate strokes per frame is the main draw cost.
    const STEPS = 24, paths = new Map();
    for (const d of drawn) {
      const key = Math.round(d.b.t * STEPS) * 2 + (d.b.p.kind === "site" ? 1 : 0);
      let path = paths.get(key);
      if (!path) paths.set(key, (path = new Path2D()));
      path.moveTo(d.base.x, d.base.y); path.lineTo(d.tip.x, d.tip.y);
    }
    // Low scores first so the best matches stay on top.
    for (const key of [...paths.keys()].sort((a, c) => a - c)) {
      const [r, gg, bl] = rampColor((key >> 1) / STEPS);
      ctx.strokeStyle = `rgba(${r | 0},${gg | 0},${bl | 0},.95)`;
      ctx.lineWidth = key & 1 ? lw * 1.6 : lw;
      ctx.stroke(paths.get(key));
    }
    g._hit = drawn;
    const placed = [];
    top.forEach((s, i) => {
      const base = g.project(s.lat, s.lon, 0, B);
      if (base.z < 0) return;
      const p = g.project(s.lat, s.lon, MARKER_ALT, B);
      ctx.strokeStyle = "rgba(255,143,184,.7)"; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.moveTo(base.x, base.y); ctx.lineTo(p.x, p.y); ctx.stroke();
      ctx.beginPath(); ctx.arc(p.x, p.y, 6.5, 0, Math.PI * 2);
      ctx.fillStyle = "#ff5fa2"; ctx.fill();
      ctx.lineWidth = 2.5; ctx.strokeStyle = "#fff"; ctx.stroke();
      labelPill(ctx, `${i + 1}. ${s.name.split(",")[0]}`, p.x, p.y - 12, { font: fontOf(600, 13), placed });
    });
    ctx.restore();
    return false;
  });

  // Nearest spike (base or tip) under the pointer.
  const hitTest = (pt) => {
    let best = null, bestD = 10;
    for (const d of globe._hit || []) {
      const dx = d.tip.x - d.base.x, dy = d.tip.y - d.base.y, len2 = dx * dx + dy * dy || 1;
      const t = Math.max(0, Math.min(1, ((pt.x - d.base.x) * dx + (pt.y - d.base.y) * dy) / len2));
      const dist = Math.hypot(pt.x - (d.base.x + t * dx), pt.y - (d.base.y + t * dy));
      if (dist < bestD || (best && dist === bestD && d.base.z > best.base.z)) { best = d; bestD = dist; }
    }
    return best ? best.b.p : null;
  };
  const topHit = (pt) => {
    const B = globe._basis();
    return top.find((s) => {
      const p = globe.project(s.lat, s.lon, MARKER_ALT, B);
      return globe.project(s.lat, s.lon, 0, B).z > 0 && Math.hypot(pt.x - p.x, pt.y - p.y) < 12;
    });
  };
  globe.onHover = (pt) => {
    if (!pt) { onHover?.(null); return; }
    const loc = hitTest(pt);
    onHover?.(loc, pt);
  };
  globe.onPick = (pt) => {
    const loc = topHit(pt) || hitTest(pt);
    if (loc) onPick?.(loc);
  };

  return {
    viewer: globe,
    get imagery() { return "Offline globe"; },

    /**
     * Draw a radial score spike for every point.
     * @param {Array} points  locations with lat/lon
     * @param {(p) => number} valueOf  score accessor
     */
    setBars(points, valueOf) {
      const vals = points.map(valueOf);
      let min = Infinity, max = -Infinity;
      for (const v of vals) { if (v < min) min = v; if (v > max) max = v; }
      const span = max - min || 1;
      bars = points.map((p, i) => ({ p, t: (vals[i] - min) / span }));
      globe.dirty = true; globe._kick();
      return { min, max };
    },

    /** Labeled markers for the top analogs. */
    setTopMarkers(t) {
      top = t;
      globe.dirty = true; globe._kick();
    },

    flyTo(lat, lon) {
      // Look from ~22° south (as globes.js does) so spikes near the target are seen side-on, not end-on.
      globe.flyTo(Math.max(-75, Math.min(75, lat - 22)), lon, 1.25, 2000);
    },

    overview() {
      globe.flyTo(15, -40, 1, 1600);
    },
  };
}
