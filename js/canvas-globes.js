// Offline globes for sandboxed / no-network builds (see tools/build_snowflake.mjs).
// Same API as globes.js, rendered with a 2D canvas orthographic projection:
// a textured Mars target picker and an Earth score map with radial score bars.

import { marsTextureCanvas } from "./mars-texture.js";
import { rampColor, fillLand, cellIndex, scoreField } from "./score-field.js";

const DEG = Math.PI / 180;
const BAR_MAX = 0.22;       // bar length at the top score, in planet radii
const BAR_MIN = 0.005;
const MARKER_ALT = BAR_MAX + 0.03;

export function cesiumAvailable() {
  return true;
}

export function initIon() {}

function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

// Canvas fonts follow the page's CSS font stacks (read once; they never change).
const fontStacks = {};
const fontOf = (weight, px, family = "--font-sans") => {
  if (!(family in fontStacks)) fontStacks[family] = getComputedStyle(document.documentElement).getPropertyValue(family).trim() || "system-ui, sans-serif";
  return `${weight} ${px}px ${fontStacks[family]}`;
};
const monoFont = (weight, px) => fontOf(weight, px, "--font-mono");
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);
const wrapLon = (l) => ((((l + 180) % 360) + 360) % 360) - 180;
const fmtLat = (v) => `${Math.abs(v).toFixed(2)}°${v >= 0 ? "N" : "S"}`;
const fmtLon = (v) => `${Math.abs(v).toFixed(2)}°${v >= 0 ? "E" : "W"}`;

/**
 * Orthographic globe on a canvas: drag to rotate, wheel / pinch to zoom,
 * click to pick, idle auto-rotation, renders only while visible.
 */
class Globe {
  constructor(el, { label = "Globe", texture = null, ocean = null, limb = "rgba(255,255,255,.25)", fit = 0.42, rotateSpeed = 4, center = [15, 0], zoom = 1, minZoom = 0.7, maxZoom = 6 }) {
    this.el = el;
    this.canvas = document.createElement("canvas");
    this.canvas.setAttribute("role", "img");
    this.canvas.setAttribute("aria-label", label);
    this.canvas.style.touchAction = "none";
    this.canvas.style.cursor = "grab";
    el.appendChild(this.canvas);
    this.ctx = this.canvas.getContext("2d");
    this.texture = texture;   // { data, w, h } equirectangular RGBA
    this.overlay = null;      // optional second texture, alpha-blended over the first
    this.ocean = ocean;
    this.limb = limb;
    this.fit = fit;           // globe radius at zoom 1, as a fraction of the shorter side
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

  get radius() { return Math.min(this.w, this.h) * this.fit * this.zoom; }

  _resize() {
    const r = this.el.getBoundingClientRect();
    this.w = Math.max(1, r.width); this.h = Math.max(1, r.height);
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = Math.round(this.w * this.dpr);
    this.canvas.height = Math.round(this.h * this.dpr);
    this.canvas.style.width = `${this.w}px`;
    this.canvas.style.height = `${this.h}px`;
    // Low-res buffer for the textured surface; scaled up with smoothing.
    const k = Math.min(1, 560 / Math.max(this.w, this.h));
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
    const tex = this.texture, ov = this.overlay;
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
        // Lambert-like light from the upper left, plus limb darkening.
        const light = Math.max(0.22, 0.4 + 0.7 * (w * 0.78 - u * 0.3 + v * 0.3));
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
          if (ov) {
            const ox = Math.min(ov.w - 1, ((lon / Math.PI + 1) / 2 * ov.w) | 0);
            const oy = Math.min(ov.h - 1, ((0.5 - lat / Math.PI) * ov.h) | 0);
            const oi = (oy * ov.w + ox) * 4, a = ov.data[oi + 3] / 255;
            if (a) { r += (ov.data[oi] - r) * a; g += (ov.data[oi + 1] - g) * a; b += (ov.data[oi + 2] - b) * a; }
          }
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
    ctx.imageSmoothingEnabled = true;
    ctx.drawImage(this.bufCanvas, 0, 0, w, h);
    // Thin atmospheric limb rather than a glow.
    ctx.strokeStyle = this.limb; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.arc(cx, cy, R + 0.5, 0, Math.PI * 2); ctx.stroke();
    this._graticule();
    let animating = false;
    for (const o of this.overlays) if (o(ctx, this, now)) animating = true;
    return animating;
  }

  _graticule() {
    const { ctx } = this, B = this._basis();
    ctx.save();
    ctx.strokeStyle = "rgba(255,255,255,.08)";
    ctx.lineWidth = 0.75;
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
    // Parallel labels along the visible central meridian, meridian labels along the
    // equator; the equator itself is identified by the meridian labels.
    ctx.font = monoFont(400, 9);
    ctx.fillStyle = "#ffffff";
    ctx.textAlign = "left"; ctx.textBaseline = "middle";
    const cl = Math.round(this.lon0 / 30) * 30;
    for (let la = -60; la <= 60; la += 30) {
      if (la === 0) continue;
      const p = this.project(la, cl, 0, B);
      if (p.z > 0.25) ctx.fillText(`${Math.abs(la)}°${la > 0 ? "N" : "S"}`, p.x + 3, p.y - 6);
    }
    for (let lo = -150; lo <= 180; lo += 30) {
      const p = this.project(0, lo, 0, B);
      if (p.z > 0.25) ctx.fillText(lo === 0 || lo === 180 ? `${Math.abs(lo)}°` : `${Math.abs(lo)}°${lo > 0 ? "E" : "W"}`, p.x + 3, p.y + 7);
    }
    ctx.restore();
  }
}

/**
 * Square-cornered label box anchored above (x, y). Pass `placed` to nudge it
 * upward past labels already drawn, and `minTop` to flip it below the anchor
 * when it would run into controls along the top edge.
 */
function labelBox(ctx, text, x, y, { font, fill = "#ffffff", bg = "rgba(3,5,10,.9)", border = "#8b9098", padX = 7, padY = 4, placed = null, minTop = -Infinity }) {
  ctx.font = font;
  const tw = ctx.measureText(text).width, th = parseFloat(font.split(" ")[1]);
  const bw = Math.round(tw + padX * 2), bh = Math.round(th + padY * 2);
  if (y - bh < minTop) y += bh + 20;
  if (placed) {
    const hits = (r) => placed.some((q) => r.x < q.x + q.w + 4 && q.x < r.x + r.w + 4 && r.y < q.y + q.h + 3 && q.y < r.y + r.h + 3);
    for (let k = 0; k < 8 && hits({ x: x - bw / 2, y: y - bh, w: bw, h: bh }); k++) y -= bh + 3;
    placed.push({ x: x - bw / 2, y: y - bh, w: bw, h: bh });
  }
  const left = Math.round(x - bw / 2) + 0.5, top = Math.round(y - bh) + 0.5;
  ctx.fillStyle = bg;
  ctx.fillRect(left, top, bw, bh);
  ctx.strokeStyle = border; ctx.lineWidth = 1;
  ctx.strokeRect(left, top, bw, bh);
  ctx.fillStyle = fill;
  ctx.textAlign = "center"; ctx.textBaseline = "middle";
  ctx.fillText(text, x, top + bh / 2 + 0.5);
}

// ===================================================================== MARS

/** Pull the procedural texture slightly toward grey so it reads like an orbital mosaic. */
function desaturate(data, amount) {
  for (let i = 0; i < data.length; i += 4) {
    const l = 0.3 * data[i] + 0.59 * data[i + 1] + 0.11 * data[i + 2];
    data[i] += (l - data[i]) * amount;
    data[i + 1] += (l - data[i + 1]) * amount;
    data[i + 2] += (l - data[i + 2]) * amount;
  }
  return data;
}

/**
 * Create the Mars viewer.
 * @param {HTMLElement} el
 * @param {{ regions: Array, onPick: (lat:number, lon:number) => void, onStatus: (msg:string) => void, onHover?: (ll: {lat:number, lon:number}|null, pos?: {x:number, y:number}) => void }} opts
 */
export async function createMarsViewer(el, { regions, onPick, onStatus, onHover }) {
  const tc = marsTextureCanvas(1024, 512);
  const texture = { data: desaturate(tc.getContext("2d").getImageData(0, 0, tc.width, tc.height).data, 0.28), w: tc.width, h: tc.height };
  const globe = new Globe(el, { label: "Interactive Mars globe: click to set the target, or use the coordinate fields", texture, limb: "rgba(230,190,160,.35)", center: [18, 77], zoom: 1, rotateSpeed: 3 });
  const source = "Mars";
  onStatus?.(source);

  let target = null;
  globe.overlays.push((ctx, g) => {
    const B = g._basis();
    ctx.save();
    // Region names near the target would collide with its reticle and label.
    const tp = target ? g.project(target.lat, target.lon, 0, B) : null;
    const nearTarget = (p) => tp && tp.z > 0 && Math.abs(p.y - tp.y) < 44 && p.x > tp.x - 170 && p.x < tp.x + 150;
    for (const r of regions) {
      const p = g.project(r.lat, r.lon, 0, B);
      if (p.z < 0.12) continue;
      ctx.globalAlpha = Math.min(1, p.z * 2.2);
      ctx.fillStyle = "rgba(255,255,255,.9)";
      ctx.fillRect(Math.round(p.x) - 2, Math.round(p.y) - 2, 4, 4);
      if (g.zoom > 0.85 && p.z > 0.3 && !nearTarget(p)) {
        ctx.globalAlpha = 1;      // labels stay pure white; only the dots fade toward the limb
        ctx.font = monoFont(500, 10);
        ctx.textAlign = "left"; ctx.textBaseline = "middle";
        ctx.lineWidth = 3; ctx.strokeStyle = "rgba(0,0,0,.75)";
        ctx.lineJoin = "round";   // mitred joins spike out of letters like M and A
        const label = r.name.toUpperCase();
        ctx.strokeText(label, p.x + 7, p.y);
        ctx.fillStyle = "#ffffff";
        ctx.fillText(label, p.x + 7, p.y);
      }
    }
    ctx.globalAlpha = 1;
    if (target) {
      const p = g.project(target.lat, target.lon, 0, B);
      if (p.z > 0) {
        // Crosshair reticle.
        const x = Math.round(p.x) + 0.5, y = Math.round(p.y) + 0.5;
        ctx.strokeStyle = "rgba(0,0,0,.6)"; ctx.lineWidth = 3;
        ctx.beginPath(); ctx.arc(x, y, 11, 0, Math.PI * 2); ctx.stroke();
        ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 1.25;
        ctx.beginPath(); ctx.arc(x, y, 11, 0, Math.PI * 2); ctx.stroke();
        ctx.beginPath();
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          ctx.moveTo(x + dx * 5, y + dy * 5); ctx.lineTo(x + dx * 18, y + dy * 18);
        }
        ctx.stroke();
        labelBox(ctx, `TARGET  ${fmtLat(target.lat)}  ${fmtLon(target.lon)}`, x, y - 24, { font: monoFont(500, 11) });
      }
    }
    ctx.restore();
    return false;
  });

  globe.onPick = (pt) => {
    const ll = globe.unproject(pt.x, pt.y);
    if (ll) onPick(ll.lat, ll.lon);
  };
  globe.onHover = (pt) => {
    const ll = pt ? globe.unproject(pt.x, pt.y) : null;
    onHover?.(ll, pt);
  };

  return {
    viewer: globe,
    source,
    setTarget(lat, lon, fly = true) {
      target = { lat, lon };
      globe.pause();
      // Rotate to the target without zooming in, so the whole disc stays in view.
      if (fly) globe.flyTo(lat, lon, globe.zoom, 1800);
      else { globe.dirty = true; globe._kick(); }
    },
  };
}

// ==================================================================== EARTH

const OCEAN = "#060b16";
const LAND = "#1a2230";

/** Rasterize land rings into an equirectangular texture (ocean + land). */
function landTexture(rings, width = 2048, height = 1024) {
  const c = document.createElement("canvas");
  c.width = width; c.height = height;
  const g = c.getContext("2d");
  g.fillStyle = OCEAN; g.fillRect(0, 0, width, height);
  g.fillStyle = LAND;
  fillLand(g, rings, width, height);
  return { data: g.getImageData(0, 0, width, height).data, w: width, h: height };
}

export async function createEarthViewer(el, { coastlines = null, gridStep = 2.5, onHover, onPick }) {
  const globe = new Globe(el, {
    label: "Earth globe of similarity scores for every tested location; the rankings and charts below list the same results",
    texture: coastlines ? landTexture(coastlines) : null,
    ocean: OCEAN,
    limb: "rgba(140,180,240,.4)",
    // Leave room for the tallest bars so the whole globe stays in frame.
    fit: 0.46 / (1 + MARKER_ALT),
    center: [15, -40], zoom: 1, minZoom: 0.6, rotateSpeed: 4,
  });
  let bars = [];        // { p: location, t: 0-1 }
  let top = [];
  let mode = "bars";
  let cellAt = () => null;
  // The smooth color field is a surface texture, rebuilt only when scores change in color mode.
  const updateField = () => {
    globe.overlay = mode === "color" && bars.length ? scoreField(bars, gridStep, coastlines) : null;
    globe.dirty = true; globe._kick();
  };

  const drawCoastlines = (ctx, g, B) => {
    if (!coastlines) return;
    ctx.beginPath();
    for (const ring of coastlines) {
      let prev = null;
      for (let k = 0; k < ring.length; k += 2) {
        const lon = ring[k], lat = ring[k + 1];
        const p = g.project(lat, lon, 0, B);
        // Break the line on the far side and across the antimeridian.
        if (p.z < 0 || (prev && Math.abs(lon - prev.lon) > 180)) { prev = p.z < 0 ? null : { lon, p }; if (prev) ctx.moveTo(p.x, p.y); continue; }
        if (prev) ctx.lineTo(p.x, p.y); else ctx.moveTo(p.x, p.y);
        prev = { lon, p };
      }
    }
    ctx.strokeStyle = "rgba(185,200,222,.5)";
    ctx.lineWidth = 0.8;
    ctx.stroke();
  };

  globe.overlays.push((ctx, g) => {
    const B = g._basis();
    ctx.save();
    drawCoastlines(ctx, g, B);
    if (mode === "bars") drawBars(ctx, g, B);
    else drawSites(ctx, g, B);
    const placed = [];
    top.forEach((s, i) => {
      const base = g.project(s.lat, s.lon, 0, B);
      if (base.z < 0) return;
      const p = mode === "bars" ? g.project(s.lat, s.lon, MARKER_ALT, B) : g.project(s.lat, s.lon, 0.06, B);
      ctx.strokeStyle = "rgba(255,255,255,.55)"; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(base.x, base.y); ctx.lineTo(p.x, p.y); ctx.stroke();
      const x = Math.round(p.x), y = Math.round(p.y);
      ctx.fillStyle = "#03050a"; ctx.fillRect(x - 5, y - 5, 10, 10);
      ctx.fillStyle = "#ffffff"; ctx.fillRect(x - 4, y - 4, 8, 8);
      // minTop keeps labels clear of the layer chips along the top of the viewer.
      labelBox(ctx, `${i + 1}  ${s.name.split(",")[0]}`, x, y - 9, { font: monoFont(500, 11), placed, minTop: 56 });
    });
    ctx.restore();
    return false;
  });

  /** Radial bars, batched into one path per color step (~1.9k separate strokes per frame is the main cost). */
  function drawBars(ctx, g, B) {
    ctx.lineCap = "butt";
    const lw = Math.max(1.4, g.radius / 150);
    const drawn = [];
    for (const b of bars) {
      const base = g.project(b.p.lat, b.p.lon, 0, B);
      if (base.z < 0) continue;
      const tip = g.project(b.p.lat, b.p.lon, BAR_MIN + b.t ** 1.6 * (BAR_MAX - BAR_MIN), B);
      drawn.push({ b, base, tip });
    }
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
      ctx.strokeStyle = `rgb(${r | 0},${gg | 0},${bl | 0})`;
      ctx.lineWidth = key & 1 ? lw * 1.7 : lw;
      ctx.stroke(paths.get(key));
    }
    g._hit = drawn;
  }

  /** Named sites as outlined squares on top of the color map. */
  function drawSites(ctx, g, B) {
    const drawn = [];
    for (const b of bars) {
      if (b.p.kind !== "site") continue;
      const p = g.project(b.p.lat, b.p.lon, 0, B);
      if (p.z < 0) continue;
      const [r, gg, bl] = rampColor(b.t);
      const x = Math.round(p.x), y = Math.round(p.y);
      ctx.fillStyle = "#03050a"; ctx.fillRect(x - 5, y - 5, 10, 10);
      ctx.fillStyle = `rgb(${r | 0},${gg | 0},${bl | 0})`; ctx.fillRect(x - 4, y - 4, 8, 8);
      drawn.push({ b, base: p, tip: p });
    }
    g._hit = drawn;
  }

  // Nearest bar (base to tip) or site square under the pointer.
  const hitTest = (pt) => {
    let best = null, bestD = 10;
    for (const d of globe._hit || []) {
      const dx = d.tip.x - d.base.x, dy = d.tip.y - d.base.y, len2 = dx * dx + dy * dy || 1;
      const t = Math.max(0, Math.min(1, ((pt.x - d.base.x) * dx + (pt.y - d.base.y) * dy) / len2));
      const dist = Math.hypot(pt.x - (d.base.x + t * dx), pt.y - (d.base.y + t * dy));
      if (dist < bestD || (best && dist === bestD && d.base.z > best.base.z)) { best = d; bestD = dist; }
    }
    if (best) return best.b.p;
    if (mode !== "color") return null;
    // Color map: the grid point whose cell contains the pointer.
    const ll = globe.unproject(pt.x, pt.y);
    return ll ? cellAt(ll.lat, ll.lon) : null;
  };
  const topHit = (pt) => {
    const B = globe._basis();
    const alt = mode === "bars" ? MARKER_ALT : 0.06;
    return top.find((s) => {
      const p = globe.project(s.lat, s.lon, alt, B);
      return globe.project(s.lat, s.lon, 0, B).z > 0 && Math.hypot(pt.x - p.x, pt.y - p.y) < 10;
    });
  };
  globe.onHover = (pt) => {
    if (!pt) { onHover?.(null); return; }
    const loc = topHit(pt) || hitTest(pt);
    globe.canvas.style.cursor = loc ? "pointer" : "grab";
    onHover?.(loc, pt);
  };
  globe.onPick = (pt) => {
    const loc = topHit(pt) || hitTest(pt);
    if (loc) onPick?.(loc);
  };

  return {
    viewer: globe,
    get imagery() { return coastlines ? "Natural Earth coastlines" : "Offline globe"; },

    /** Map style: "bars" (radial bars) or "color" (smooth score field over land). Applies on the next setBars. */
    setMode(m) { mode = m === "color" ? "color" : "bars"; },

    /**
     * Set the score shown for every point.
     * @param {Array} points  locations with lat/lon
     * @param {(p) => number} valueOf  score accessor
     */
    setBars(points, valueOf) {
      const vals = points.map(valueOf);
      let min = Infinity, max = -Infinity;
      for (const v of vals) { if (v == null) continue; if (v < min) min = v; if (v > max) max = v; }
      const span = max - min || 1;
      bars = points.map((p, i) => ({ p, t: vals[i] == null ? 0 : (vals[i] - min) / span })).filter((b, i) => vals[i] != null);
      cellAt = cellIndex(bars.map((b) => b.p), gridStep);
      updateField();
      return { min, max };
    },

    /** Labeled markers for the top analogs. */
    setTopMarkers(t) {
      top = t;
      globe.dirty = true; globe._kick();
    },

    flyTo(lat, lon) {
      // Whole globe stays in frame; look from ~18° south so bars near the target are seen side-on.
      globe.flyTo(Math.max(-70, Math.min(70, lat - 18)), lon, 1, 2000);
    },

    overview() {
      globe.flyTo(15, -40, 1, 1600);
    },
  };
}
