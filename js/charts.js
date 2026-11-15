// Chart.js visualizations.

import { CRITERIA, CATEGORIES } from "./criteria.js";

export const TOP_COLORS = ["#ff5fa2", "#b388ff", "#7cb8ff", "#6ff0d6", "#ffd27a"];
const catColor = (c) => CATEGORIES.find((x) => x.id === c.category).color;
const charts = {};

export function chartsAvailable() {
  return typeof window.Chart !== "undefined";
}

export function setupChartDefaults() {
  if (!chartsAvailable()) return;
  const Ch = window.Chart;
  Ch.defaults.font.family = "Quicksand, Fredoka, ui-rounded, 'SF Pro Rounded', Nunito, system-ui, sans-serif";
  Ch.defaults.font.weight = 600;
  Ch.defaults.color = "#a7a0cc";
  Ch.defaults.borderColor = "rgba(255,255,255,0.07)";
  Ch.defaults.animation.duration = 1100;
  Ch.defaults.animation.easing = "easeOutQuart";
  Ch.defaults.plugins.legend.labels.usePointStyle = true;
  Ch.defaults.plugins.legend.labels.boxWidth = 8;
  Ch.defaults.plugins.legend.labels.padding = 16;
  Object.assign(Ch.defaults.plugins.tooltip, {
    backgroundColor: "rgba(20, 12, 44, 0.94)",
    borderColor: "rgba(179, 136, 255, 0.45)",
    borderWidth: 1,
    padding: 12,
    cornerRadius: 12,
    titleFont: { family: "Fredoka, ui-rounded, 'SF Pro Rounded', Nunito, system-ui, sans-serif", size: 13, weight: 600 },
    bodyFont: { family: "Quicksand, ui-rounded, 'SF Pro Rounded', Nunito, system-ui, sans-serif", size: 12, weight: 600 },
  });
}

function draw(id, config) {
  const canvas = document.getElementById(id);
  if (!canvas) return null;
  if (!chartsAvailable()) {
    canvas.parentElement.innerHTML = '<div class="chart-fallback">Charts unavailable (Chart.js failed to load)</div>';
    return null;
  }
  if (charts[id]) charts[id].destroy();
  charts[id] = new window.Chart(canvas, config);
  return charts[id];
}

function verticalGradient(ctx, area, top, bottom) {
  const g = ctx.createLinearGradient(0, area.bottom, 0, area.top);
  g.addColorStop(0, bottom);
  g.addColorStop(1, top);
  return g;
}

const short = (name) => name.split(",")[0];
const scaleY01 = { min: 0, max: 1, ticks: { stepSize: 0.2 }, grid: { color: "rgba(255,255,255,0.06)" } };

export function metricLabel(metric) {
  return metric === "total" ? "Total score" : CRITERIA.find((c) => c.id === metric).name;
}
const metricValue = (loc, metric) => (metric === "total" ? loc.total : loc.scores[metric]);

/** Grouped bars: top 5 × every criterion. */
export function drawGrouped(top) {
  draw("groupedChart", {
    type: "bar",
    data: {
      labels: CRITERIA.map((c) => c.short),
      datasets: top.map((s, i) => ({
        label: `${i + 1}. ${short(s.name)}`,
        data: CRITERIA.map((c) => s.scores[c.id]),
        backgroundColor: (ctx) => ctx.chart.chartArea
          ? verticalGradient(ctx.chart.ctx, ctx.chart.chartArea, TOP_COLORS[i], TOP_COLORS[i] + "33")
          : TOP_COLORS[i],
        borderRadius: 6,
        borderSkipped: false,
        maxBarThickness: 22,
      })),
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      scales: { y: scaleY01, x: { grid: { display: false } } },
      plugins: { tooltip: { callbacks: { label: (c) => ` ${c.dataset.label}: ${c.parsed.y.toFixed(3)}` } } },
    },
  });
}

/** Horizontal bar of the 10 best named sites on one metric. */
export function drawMetric(sites, metric, selectedId) {
  const ranked = [...sites].sort((a, b) => metricValue(b, metric) - metricValue(a, metric)).slice(0, 10);
  draw("metricChart", {
    type: "bar",
    data: {
      labels: ranked.map((s) => short(s.name)),
      datasets: [{
        label: metricLabel(metric),
        data: ranked.map((s) => metricValue(s, metric)),
        backgroundColor: (ctx) => {
          const area = ctx.chart.chartArea;
          if (!area) return "#b388ff";
          const g = ctx.chart.ctx.createLinearGradient(area.left, 0, area.right, 0);
          g.addColorStop(0, "#4f8cff"); g.addColorStop(0.5, "#8b5cf6"); g.addColorStop(1, "#ff5fa2");
          return g;
        },
        borderColor: ranked.map((s) => (s.id === selectedId ? "#ffffff" : "transparent")),
        borderWidth: 2,
        borderRadius: 8,
        borderSkipped: false,
        barThickness: 14,
      }],
    },
    options: {
      indexAxis: "y",
      responsive: true, maintainAspectRatio: false,
      scales: { x: { ...scaleY01 }, y: { grid: { display: false } } },
      plugins: { legend: { display: false }, tooltip: { callbacks: { label: (c) => ` ${metricLabel(metric)}: ${c.parsed.x.toFixed(3)}` } } },
    },
  });
}

/** Doughnut of the applied (normalized) weights. */
export function drawWeights(weights) {
  draw("weightChart", {
    type: "doughnut",
    data: {
      labels: CRITERIA.map((c) => c.short),
      datasets: [{
        data: weights,
        backgroundColor: CRITERIA.map((c, i) => catColor(c) + (i % 2 ? "cc" : "ff")),
        borderColor: "rgba(10, 5, 25, 0.9)",
        borderWidth: 3,
        hoverOffset: 10,
      }],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      cutout: "62%",
      plugins: {
        legend: { position: "right" },
        tooltip: { callbacks: { label: (c) => ` ${c.label}: ${(c.parsed * 100).toFixed(1)}%` } },
      },
    },
  });
}

/** Scatter of all tested locations on two selectable metrics. */
export function drawScatter(all, top, xMetric, yMetric) {
  const topIds = new Set(top.map((t) => t.id));
  const grid = all.filter((l) => l.kind === "grid");
  const sites = all.filter((l) => l.kind === "site" && !topIds.has(l.id));
  const pt = (l) => ({ x: metricValue(l, xMetric), y: metricValue(l, yMetric), name: l.name });
  draw("scatterChart", {
    type: "scatter",
    data: {
      datasets: [
        { label: `Grid cells (${grid.length})`, data: grid.map(pt), pointRadius: 2.2, pointHoverRadius: 5, backgroundColor: "rgba(124, 184, 255, 0.35)", borderWidth: 0 },
        { label: `Named analog sites (${sites.length})`, data: sites.map(pt), pointRadius: 5, pointHoverRadius: 8, backgroundColor: "rgba(179, 136, 255, 0.85)", borderColor: "#fff", borderWidth: 1 },
        { label: "Top 5", data: top.map(pt), pointRadius: 9, pointHoverRadius: 12, pointStyle: "star", backgroundColor: "#ff5fa2", borderColor: "#ff5fa2", borderWidth: 3 },
      ],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      scales: {
        x: { min: 0, max: 1, title: { display: true, text: metricLabel(xMetric) }, grid: { color: "rgba(255,255,255,0.05)" } },
        y: { min: 0, max: 1, title: { display: true, text: metricLabel(yMetric) }, grid: { color: "rgba(255,255,255,0.05)" } },
      },
      plugins: {
        tooltip: { callbacks: { label: (c) => ` ${c.raw.name}: (${c.raw.x.toFixed(2)}, ${c.raw.y.toFixed(2)})` } },
      },
    },
  });
}

/** Radar of one location vs the mean of all tested locations. */
export function drawRadar(loc, means) {
  draw("radarChart", {
    type: "radar",
    data: {
      labels: CRITERIA.map((c) => c.short),
      datasets: [
        {
          label: short(loc.name),
          data: CRITERIA.map((c) => loc.scores[c.id]),
          backgroundColor: "rgba(255, 95, 162, 0.22)",
          borderColor: "#ff5fa2",
          pointBackgroundColor: CRITERIA.map(catColor),
          pointBorderColor: "#fff",
          pointRadius: 4,
          borderWidth: 2,
        },
        {
          label: "Mean of all tested",
          data: means,
          backgroundColor: "rgba(124, 184, 255, 0.08)",
          borderColor: "rgba(124, 184, 255, 0.7)",
          borderDash: [5, 4],
          pointRadius: 0,
          borderWidth: 1.5,
        },
      ],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      scales: {
        r: {
          min: 0, max: 1,
          ticks: { display: false, stepSize: 0.25 },
          grid: { color: "rgba(255,255,255,0.08)" },
          angleLines: { color: "rgba(255,255,255,0.08)" },
          pointLabels: { font: { size: 11, weight: 600 }, color: "#cfc8ee" },
        },
      },
      plugins: { legend: { position: "bottom" } },
    },
  });
}
