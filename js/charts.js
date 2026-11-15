// Chart.js visualizations, styled after spreadsheet charts: flat square bars,
// light gridlines, square legend swatches, axis titles.

import { CRITERIA } from "./criteria.js";
import { rampColor } from "./score-field.js";

// Google Slides chart palette: one bright color per series or bar.
const PALETTE = ["#4285F4", "#EA4335", "#FBBC04", "#34A853", "#FF6D01", "#46BDC6", "#AB47BC", "#F06292", "#9CCC65", "#FFA726"];
export const TOP_COLORS = PALETTE.slice(0, 5);
const MEAN_COLOR = "#5f6773";
const GRID = "rgba(255,255,255,0.12)";
const AXIS = "#8b9098";
const SANS = "'Noto Sans', sans-serif";
const HEAD = "'Narwal', 'Noto Sans', sans-serif";
// Numbers use Noto Sans like the rest of the page.
const MONO = SANS;
const charts = {};

export function chartsAvailable() {
  return typeof window.Chart !== "undefined";
}

export function setupChartDefaults() {
  if (!chartsAvailable()) return;
  const Ch = window.Chart;
  Ch.defaults.font.family = SANS;
  Ch.defaults.font.size = 14;
  Ch.defaults.font.weight = 400;
  Ch.defaults.color = "#ffffff";
  Ch.defaults.borderColor = GRID;
  Ch.defaults.animation.duration = 500;
  Ch.defaults.animation.easing = "easeOutCubic";
  Object.assign(Ch.defaults.plugins.legend, { position: "top", align: "start" });
  Object.assign(Ch.defaults.plugins.legend.labels, { usePointStyle: false, boxWidth: 12, boxHeight: 12, padding: 14, color: "#ffffff" });
  Object.assign(Ch.defaults.plugins.tooltip, {
    backgroundColor: "rgba(5, 8, 15, 0.97)",
    borderColor: "rgba(255,255,255,0.22)",
    borderWidth: 2,
    padding: 10,
    cornerRadius: 2,
    boxPadding: 4,
    usePointStyle: false,
    titleColor: "#ffffff",
    bodyColor: "#ffffff",
    titleFont: { family: HEAD, weight: 700, size: 15 },
    bodyFont: { family: MONO, size: 14 },
  });
  Ch.defaults.elements.bar.borderRadius = 0;
  Ch.defaults.elements.bar.borderSkipped = "start";
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

const short = (name) => name.split(",")[0];
const axisTitle = (text) => ({ display: true, text, color: "#ffffff", font: { size: 14, weight: 600 } });
const value01 = (title) => ({
  min: 0, max: 1,
  ticks: { stepSize: 0.2, font: { family: MONO, size: 14 } },
  grid: { color: GRID },
  border: { color: AXIS },
  title: title ? axisTitle(title) : undefined,
});
const category = () => ({ grid: { display: false }, border: { color: AXIS } });

export function metricLabel(metric) {
  return metric === "total" ? "Total score" : CRITERIA.find((c) => c.id === metric).name;
}
const metricValue = (loc, metric) => (metric === "total" ? loc.total : loc.scores[metric]);

/** Clustered columns: top 5 × every criterion. */
export function drawGrouped(top) {
  draw("groupedChart", {
    type: "bar",
    data: {
      labels: CRITERIA.map((c) => c.short),
      datasets: top.map((s, i) => ({
        label: `${i + 1}. ${short(s.name)}`,
        data: CRITERIA.map((c) => s.scores[c.id]),
        backgroundColor: TOP_COLORS[i],
        maxBarThickness: 18,
        categoryPercentage: 0.78,
        barPercentage: 0.92,
      })),
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      scales: { y: value01("Similarity"), x: category() },
      plugins: { tooltip: { callbacks: { label: (c) => ` ${c.dataset.label}: ${c.parsed.y.toFixed(3)}` } } },
    },
  });
}

/** Horizontal bars: the 10 best named sites on one metric. */
export function drawMetric(sites, metric, selectedId) {
  const ranked = [...sites].sort((a, b) => metricValue(b, metric) - metricValue(a, metric)).slice(0, 10);
  draw("metricChart", {
    type: "bar",
    data: {
      labels: ranked.map((s) => short(s.name)),
      datasets: [{
        label: metricLabel(metric),
        data: ranked.map((s) => metricValue(s, metric)),
        backgroundColor: ranked.map((s, i) => PALETTE[i % PALETTE.length]),
        borderColor: ranked.map((s) => (s.id === selectedId ? "#ffffff" : "transparent")),
        borderWidth: ranked.map((s) => (s.id === selectedId ? 3 : 0)),
        borderSkipped: false,
        barPercentage: 0.75,
        categoryPercentage: 0.9,
      }],
    },
    options: {
      indexAxis: "y",
      responsive: true, maintainAspectRatio: false,
      scales: { x: value01(metricLabel(metric)), y: category() },
      plugins: { legend: { display: false }, tooltip: { callbacks: { label: (c) => ` ${metricLabel(metric)}: ${c.parsed.x.toFixed(3)}` } } },
    },
  });
}

/** Horizontal bars of the applied (normalized) weights, largest first. */
export function drawWeights(weights) {
  const rows = CRITERIA.map((c, k) => ({ label: c.short, w: weights[k] })).sort((a, b) => b.w - a.w);
  const max = Math.max(...rows.map((r) => r.w));
  draw("weightChart", {
    type: "bar",
    data: {
      labels: rows.map((r) => r.label),
      datasets: [{ label: "Weight", data: rows.map((r) => r.w * 100), backgroundColor: rows.map((r, i) => PALETTE[i % PALETTE.length]), barPercentage: 0.75, categoryPercentage: 0.9 }],
    },
    options: {
      indexAxis: "y",
      responsive: true, maintainAspectRatio: false,
      scales: {
        x: {
          min: 0, suggestedMax: Math.ceil(max * 100 / 5) * 5,
          ticks: { callback: (v) => `${v}%`, font: { family: MONO, size: 14 } },
          grid: { color: GRID }, border: { color: AXIS }, title: axisTitle("Share of total weight"),
        },
        y: category(),
      },
      plugins: { legend: { display: false }, tooltip: { callbacks: { label: (c) => ` ${c.parsed.x.toFixed(1)}%` } } },
    },
  });
}

/** Scatter of all tested locations on two selectable metrics. */
export function drawScatter(all, top, xMetric, yMetric) {
  const topIds = new Set(top.map((t) => t.id));
  const grid = all.filter((l) => l.kind === "grid");
  const sites = all.filter((l) => l.kind === "site" && !topIds.has(l.id));
  const pt = (l) => ({ x: metricValue(l, xMetric), y: metricValue(l, yMetric), name: l.name });
  // Fit each axis to the data (rounded down to 0.1), as spreadsheet charts do.
  const points = all.map(pt);
  const floor01 = (vals) => Math.max(0, Math.floor((Math.min(...vals) - 0.02) * 10) / 10);
  const xAxis = { ...value01(metricLabel(xMetric)), min: floor01(points.map((p) => p.x)), ticks: { ...value01().ticks, stepSize: 0.1 } };
  const yAxis = { ...value01(metricLabel(yMetric)), min: floor01(points.map((p) => p.y)), ticks: { ...value01().ticks, stepSize: 0.1 } };
  draw("scatterChart", {
    type: "scatter",
    data: {
      datasets: [
        { label: `Grid cells (${grid.length.toLocaleString("en-US")})`, data: grid.map(pt), pointRadius: 1.8, pointHoverRadius: 4, backgroundColor: "rgba(154, 160, 166, 0.45)", borderWidth: 0 },
        { label: `Named analog sites (${sites.length})`, data: sites.map(pt), pointRadius: 4, pointHoverRadius: 6, backgroundColor: "#46BDC6", borderWidth: 0 },
        { label: "Top 5", data: top.map(pt), pointRadius: 7, pointHoverRadius: 9, pointStyle: "rect", backgroundColor: TOP_COLORS, borderColor: "#ffffff", borderWidth: 1.5 },
      ],
    },
    options: {
      responsive: true, maintainAspectRatio: false,
      scales: { x: xAxis, y: yAxis },
      plugins: {
        legend: { labels: { usePointStyle: true, pointStyle: "rect" } },
        tooltip: { callbacks: { label: (c) => ` ${c.raw.name}: (${c.raw.x.toFixed(2)}, ${c.raw.y.toFixed(2)})` } },
      },
    },
  });
}

/** Paired horizontal bars: one location vs the mean of all tested locations, per criterion. */
export function drawProfile(loc, means) {
  draw("profileChart", {
    type: "bar",
    data: {
      labels: CRITERIA.map((c) => c.short),
      datasets: [
        { label: short(loc.name), data: CRITERIA.map((c) => loc.scores[c.id]), backgroundColor: TOP_COLORS[0], barPercentage: 0.9, categoryPercentage: 0.8 },
        { label: "Mean of all tested", data: means, backgroundColor: MEAN_COLOR, barPercentage: 0.9, categoryPercentage: 0.8 },
      ],
    },
    options: {
      indexAxis: "y",
      responsive: true, maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      scales: { x: value01("Similarity"), y: category() },
      plugins: { tooltip: { callbacks: { label: (c) => ` ${c.dataset.label}: ${c.parsed.x.toFixed(3)}` } } },
    },
  });
}

/** Draws each bar's value just past its end, as Slides charts do. */
const valueLabels = {
  id: "valueLabels",
  afterDatasetsDraw(chart) {
    const { ctx } = chart, meta = chart.getDatasetMeta(0);
    ctx.save();
    ctx.font = `600 14px ${SANS}`;
    ctx.fillStyle = "#ffffff"; ctx.textBaseline = "middle"; ctx.textAlign = "left";
    meta.data.forEach((bar, i) => ctx.fillText(chart.data.datasets[0].data[i].toFixed(3), bar.x + 6, bar.y));
    ctx.restore();
  },
};

/**
 * Chart view of the Earth map: one page of ranked locations as horizontal
 * bars, colored with the map's score ramp (t is the 0-1 position used for the
 * map colors). Top 5 labels are bold; the selected bar is outlined.
 * @param {Array<{ loc, value, t, rank, label }>} rows  one page, in display order
 */
export function drawRanking(rows, { metric, total, topIds, selectedId, onPick }) {
  draw("rankChart", {
    type: "bar",
    data: {
      labels: rows.map((r) => r.label),
      datasets: [{
        label: metricLabel(metric),
        data: rows.map((r) => r.value),
        backgroundColor: rows.map((r) => { const [cr, cg, cb] = rampColor(r.t); return `rgb(${cr | 0},${cg | 0},${cb | 0})`; }),
        borderColor: rows.map((r) => (r.loc.id === selectedId ? "#ffffff" : "transparent")),
        borderWidth: rows.map((r) => (r.loc.id === selectedId ? 3 : 0)),
        borderSkipped: false,
        barPercentage: 0.8,
        categoryPercentage: 0.9,
      }],
    },
    options: {
      indexAxis: "y",
      responsive: true, maintainAspectRatio: false,
      animation: { duration: 300 },
      layout: { padding: { right: 56 } },
      scales: {
        x: value01(metricLabel(metric)),
        y: {
          grid: { display: false }, border: { color: AXIS },
          ticks: { autoSkip: false, font: (c) => ({ family: SANS, size: 14, weight: topIds.has(rows[c.index]?.loc.id) ? 700 : 400 }) },
        },
      },
      // Picking redraws this chart, so wait until Chart.js has finished handling the click.
      onClick: (e, els) => { if (els[0]) { const loc = rows[els[0].index].loc; setTimeout(() => onPick(loc), 0); } },
      onHover: (e, els) => { e.native.target.style.cursor = els.length ? "pointer" : "default"; },
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            title: (items) => rows[items[0].dataIndex].name,
            label: (c) => {
              const r = rows[c.dataIndex];
              return [` ${metricLabel(metric)}: ${r.value.toFixed(3)}`, ` Rank ${r.rank.toLocaleString("en-US")} of ${total.toLocaleString("en-US")}`, ` ${r.coords}`];
            },
          },
        },
      },
    },
    plugins: [valueLabels],
  });
}
