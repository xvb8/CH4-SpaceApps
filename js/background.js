// Animated starfield: parallax star layers, twinkling, occasional shooting stars
// and a gentle mouse/scroll parallax. Pauses when the tab is hidden.

export function startStarfield(canvas) {
  const ctx = canvas.getContext("2d");
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const PALETTE = ["#ffffff", "#ffffff", "#e6dcff", "#cfe3ff", "#ffd6e8", "#fff4d6"];
  let w = 0, h = 0, dpr = 1, stars = [], meteors = [];
  let mx = 0, my = 0, tx = 0, ty = 0, scrollY = window.scrollY;
  let last = performance.now(), running = true;

  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    w = window.innerWidth; h = window.innerHeight;
    canvas.width = w * dpr; canvas.height = h * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const count = Math.round((w * h) / 2600);
    stars = Array.from({ length: count }, () => {
      const depth = Math.random() ** 2;           // most stars are far away
      return {
        x: Math.random() * w,
        y: Math.random() * h,
        r: 0.25 + depth * 1.5,
        depth,
        base: 0.35 + Math.random() * 0.6,
        tw: 0.5 + Math.random() * 2.5,            // twinkle speed
        ph: Math.random() * Math.PI * 2,
        c: PALETTE[(Math.random() * PALETTE.length) | 0],
      };
    });
  }

  function spawnMeteor() {
    const fromLeft = Math.random() < 0.5;
    meteors.push({
      x: fromLeft ? Math.random() * w * 0.6 : w * 0.4 + Math.random() * w * 0.6,
      y: Math.random() * h * 0.45,
      vx: (fromLeft ? 1 : -1) * (520 + Math.random() * 420),
      vy: 220 + Math.random() * 200,
      life: 0,
      max: 0.9 + Math.random() * 0.6,
    });
  }

  function frame(now) {
    if (!running) return;
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    tx += (mx - tx) * 0.04; ty += (my - ty) * 0.04;
    const sy = window.scrollY;
    scrollY += (sy - scrollY) * 0.1;

    ctx.clearRect(0, 0, w, h);
    const t = now / 1000;
    for (const s of stars) {
      const px = s.x + tx * s.depth * 24;
      let py = s.y + ty * s.depth * 24 - scrollY * s.depth * 0.12;
      py = ((py % h) + h) % h;
      const a = reduced ? s.base : s.base * (0.55 + 0.45 * Math.sin(t * s.tw + s.ph));
      ctx.globalAlpha = a;
      ctx.fillStyle = s.c;
      ctx.beginPath();
      ctx.arc(px, py, s.r, 0, Math.PI * 2);
      ctx.fill();
      if (s.r > 1.35) {                            // soft glow on the brightest stars
        ctx.globalAlpha = a * 0.18;
        ctx.beginPath();
        ctx.arc(px, py, s.r * 4, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    if (!reduced && Math.random() < dt * 0.18) spawnMeteor();
    for (const m of meteors) {
      m.life += dt;
      m.x += m.vx * dt; m.y += m.vy * dt;
      const k = 1 - m.life / m.max;
      const len = 0.09;
      const g = ctx.createLinearGradient(m.x, m.y, m.x - m.vx * len, m.y - m.vy * len);
      g.addColorStop(0, `rgba(255,255,255,${0.9 * k})`);
      g.addColorStop(0.3, `rgba(255,143,184,${0.45 * k})`);
      g.addColorStop(1, "rgba(139,92,246,0)");
      ctx.globalAlpha = 1;
      ctx.strokeStyle = g;
      ctx.lineWidth = 1.6;
      ctx.beginPath();
      ctx.moveTo(m.x, m.y);
      ctx.lineTo(m.x - m.vx * len, m.y - m.vy * len);
      ctx.stroke();
    }
    meteors = meteors.filter((m) => m.life < m.max);
    ctx.globalAlpha = 1;
    requestAnimationFrame(frame);
  }

  window.addEventListener("resize", resize);
  window.addEventListener("pointermove", (e) => {
    mx = e.clientX / w - 0.5;
    my = e.clientY / h - 0.5;
  }, { passive: true });
  document.addEventListener("visibilitychange", () => {
    running = !document.hidden;
    if (running) { last = performance.now(); requestAnimationFrame(frame); }
  });

  resize();
  requestAnimationFrame(frame);
}
