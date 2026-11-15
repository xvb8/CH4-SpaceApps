// Images of any Earth location, looked up by latitude/longitude at runtime.
//
// Ground-level image, first source with coverage wins:
//   1. Google Street View (needs CONFIG.googleMapsKey). The nearest outdoor
//      panorama within 1, 10, then 100 km is found with the Maps JavaScript
//      API (the Street View metadata endpoint is tried if that API cannot
//      load). It is shown as a Street View Static image when that API is
//      enabled for the key, otherwise as a Maps JavaScript panorama.
//   2. Mapillary street-level photos (needs CONFIG.mapillaryToken).
//   3. Wikimedia Commons photos geotagged within 10 km (no key).
// Satellite view (always available): Esri World Imagery, centred on the point.
//
// Every Google failure is logged to the console with the reason, so a key
// that is restricted or missing an API is easy to spot.

import { CONFIG } from "./config.js";

const cache = new Map();
const RADII_M = [1_000, 10_000, 100_000];
let googleDenied = false;
let mapsJs = null;
const warned = new Set();
const deniedListeners = new Set();

/**
 * Google can reject the key after a panorama has already been drawn (it then
 * shows its own "can't load Google Maps" box). Stop using Google, drop cached
 * Street View results, and tell whoever is showing images to swap them out.
 */
function denyGoogle(reason) {
  if (googleDenied) return;
  googleDenied = true;
  warn(reason);
  cache.clear();   // lookups run again without Google
  deniedListeners.forEach((cb) => cb());
}

/** Run `cb` once if Google rejects the key; returns an unsubscribe function. */
export function onGoogleDenied(cb) {
  if (googleDenied) { cb(); return () => {}; }
  const once = () => { deniedListeners.delete(once); cb(); };
  deniedListeners.add(once);
  return () => deniedListeners.delete(once);
}

const warn = (msg) => { if (!warned.has(msg)) { warned.add(msg); console.warn(`Street View: ${msg}`); } };
const rad = Math.PI / 180;
const km = (a, b) => {
  const dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(h));
};
/** Compass bearing from a to b, so the camera faces the location itself. */
const bearing = (a, b) => {
  const y = Math.sin((b.lon - a.lon) * rad) * Math.cos(b.lat * rad);
  const x = Math.cos(a.lat * rad) * Math.sin(b.lat * rad) - Math.sin(a.lat * rad) * Math.cos(b.lat * rad) * Math.cos((b.lon - a.lon) * rad);
  return (Math.atan2(y, x) / rad + 360) % 360;
};
const withTimeout = (p, ms, what) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error(`${what} timed out`)), ms))]);
const getJSON = async (url) => {
  const r = await withTimeout(fetch(url), 8000, "request");
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
};
const stripHtml = (s) => (s || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim();

export function photosAvailable() { return true; }

/**
 * @returns {Promise<{ ground: Image | null, satellite: Image }>}
 *   Image = { kind, src, source, credit, link, distanceKm, date, pano?, heading? }
 */
export function imagesFor(lat, lon) {
  const key = `${lat.toFixed(4)},${lon.toFixed(4)}`;
  if (!cache.has(key)) {
    const at = { lat, lon };
    cache.set(key, (async () => {
      let ground = null;
      for (const find of [streetView, mapillary, commons]) {
        try { ground = await find(at); } catch (err) { if (find === streetView) warn(err.message); ground = null; }
        if (ground) break;
      }
      return { ground, satellite: satellite(at) };
    })());
  }
  return cache.get(key);
}

// ------------------------------------------------------------ Google Street View
function loadMapsJs() {
  if (window.google?.maps?.StreetViewService) return Promise.resolve(window.google.maps);
  if (!mapsJs) {
    mapsJs = new Promise((resolve, reject) => {
      const cb = "__ch4MapsReady";
      window[cb] = () => resolve(window.google.maps);
      // Google calls this when the key is invalid, restricted for this site, or lacks the Maps JavaScript API.
      window.gm_authFailure = () => denyGoogle("the key was rejected (check that the Maps JavaScript API is enabled, billing is set up, and this site is allowed under Website restrictions)");
      const s = document.createElement("script");
      s.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(CONFIG.googleMapsKey)}&loading=async&callback=${cb}`;
      s.async = true;
      s.onerror = () => reject(new Error("the Maps JavaScript API could not be loaded"));
      document.head.appendChild(s);
    });
  }
  return withTimeout(mapsJs, 12_000, "loading the Maps JavaScript API");
}

async function streetView(at) {
  if (!CONFIG.googleMapsKey || googleDenied) return null;
  let find;
  try {
    const maps = await loadMapsJs();
    const svc = new maps.StreetViewService();
    find = (radius) => panoViaMapsJs(maps, svc, at, radius);
  } catch (err) {
    warn(`${err.message}; trying the metadata endpoint`);
    find = (radius) => panoViaMetadata(at, radius);
  }
  for (const radius of RADII_M) {
    if (googleDenied) return null;
    const pano = await find(radius);
    if (!pano) continue;
    const heading = km(pano.location, at) > 0.05 ? bearing(pano.location, at) : 0;
    const q = new URLSearchParams({ size: "640x360", pano: pano.id, heading: heading.toFixed(0), fov: "90", pitch: "0", key: CONFIG.googleMapsKey });
    return {
      kind: "streetview",
      pano: pano.id, heading,
      src: `https://maps.googleapis.com/maps/api/streetview?${q}`,
      source: "Google Street View",
      credit: pano.copyright || "© Google",
      link: `https://www.google.com/maps/@?api=1&map_action=pano&pano=${encodeURIComponent(pano.id)}&heading=${heading.toFixed(0)}`,
      distanceKm: km(at, pano.location),
      date: pano.date || "",
    };
  }
  return null;
}

async function panoViaMapsJs(maps, svc, at, radius) {
  try {
    const { data } = await withTimeout(svc.getPanorama({
      location: { lat: at.lat, lng: at.lon }, radius,
      source: maps.StreetViewSource.OUTDOOR, preference: maps.StreetViewPreference.NEAREST,
    }), 10_000, "the panorama search");
    const ll = data.location.latLng;
    return { id: data.location.pano, location: { lat: ll.lat(), lon: ll.lng() }, date: data.imageDate, copyright: data.copyright };
  } catch (err) {
    const code = String(err?.code || err?.message || err);
    if (/ZERO_RESULTS/.test(code)) return null;
    if (/REQUEST_DENIED|OVER_QUERY_LIMIT/.test(code)) { denyGoogle(`${code} from the Maps JavaScript API`); return null; }
    warn(code);
    return null;
  }
}

async function panoViaMetadata(at, radius) {
  const q = new URLSearchParams({ location: `${at.lat},${at.lon}`, radius: String(radius), source: "outdoor", key: CONFIG.googleMapsKey });
  const meta = await getJSON(`https://maps.googleapis.com/maps/api/streetview/metadata?${q}`);
  if (meta.status === "OK") return { id: meta.pano_id, location: { lat: meta.location.lat, lon: meta.location.lng }, date: meta.date, copyright: meta.copyright };
  if (meta.status !== "ZERO_RESULTS" && meta.status !== "NOT_FOUND") {
    denyGoogle(`${meta.status} from the metadata endpoint${meta.error_message ? `: ${meta.error_message}` : ""}`);
  }
  return null;
}

/**
 * Render a Street View panorama into `el` with the Maps JavaScript API.
 * `interactive: false` gives a still view (for cards); true allows looking around.
 * Resolves true once the panorama has loaded, false if it cannot be shown.
 */
export async function mountStreetView(el, im, { interactive = true } = {}) {
  if (googleDenied) return false;
  let maps;
  try { maps = await loadMapsJs(); } catch (err) { warn(err.message); return false; }
  return new Promise((resolve) => {
    const pano = new maps.StreetViewPanorama(el, {
      pano: im.pano,
      pov: { heading: im.heading || 0, pitch: 0 },
      zoom: 0,
      disableDefaultUI: !interactive,
      addressControl: false, fullscreenControl: interactive, motionTracking: false, motionTrackingControl: false,
      showRoadLabels: false, linksControl: interactive, panControl: false, zoomControl: interactive,
      clickToGo: interactive, scrollwheel: false, enableCloseButton: false,
    });
    const done = (ok) => { clearTimeout(timer); resolve(ok && !googleDenied); };
    const timer = setTimeout(() => done(false), 10_000);
    pano.addListener("status_changed", () => {
      const status = pano.getStatus();
      if (status === "OK") done(true);
      else { warn(`panorama status ${status}`); done(false); }
    });
  });
}

// ------------------------------------------------------------------ Mapillary
async function mapillary(at) {
  const token = CONFIG.mapillaryToken;
  if (!token) return null;
  // Mapillary limits bbox size, so search a ~10 km box and pick the closest image.
  const d = 0.05, dl = d / Math.max(0.2, Math.cos(at.lat * rad));
  const q = new URLSearchParams({
    access_token: token, fields: "id,thumb_1024_url,captured_at,geometry,creator",
    bbox: [at.lon - dl, at.lat - d, at.lon + dl, at.lat + d].map((v) => v.toFixed(5)).join(","), limit: "50",
  });
  const { data = [] } = await getJSON(`https://graph.mapillary.com/images?${q}`);
  const best = data
    .map((im) => ({ im, dist: km(at, { lat: im.geometry.coordinates[1], lon: im.geometry.coordinates[0] }) }))
    .sort((a, b) => a.dist - b.dist)[0];
  if (!best?.im.thumb_1024_url) return null;
  return {
    kind: "photo",
    src: best.im.thumb_1024_url,
    source: "Mapillary",
    credit: `© ${best.im.creator?.username || "Mapillary contributor"}, CC BY-SA`,
    link: `https://www.mapillary.com/app/?pKey=${best.im.id}`,
    distanceKm: best.dist,
    date: best.im.captured_at ? new Date(best.im.captured_at).toISOString().slice(0, 10) : "",
  };
}

// ----------------------------------------------------------- Wikimedia Commons
async function commons(at) {
  const q = new URLSearchParams({
    action: "query", format: "json", origin: "*",
    generator: "geosearch", ggscoord: `${at.lat}|${at.lon}`, ggsradius: "10000", ggslimit: "20", ggsnamespace: "6",
    prop: "imageinfo|coordinates", iiprop: "url|mime|extmetadata", iiurlwidth: "640",
  });
  const json = await getJSON(`https://commons.wikimedia.org/w/api.php?${q}`);
  const pages = Object.values(json.query?.pages || {});
  const best = pages
    .filter((p) => /^image\/(jpeg|png|webp)$/.test(p.imageinfo?.[0]?.mime || "") && p.coordinates?.[0])
    .map((p) => ({ p, dist: km(at, { lat: p.coordinates[0].lat, lon: p.coordinates[0].lon }) }))
    .sort((a, b) => a.dist - b.dist)[0];
  if (!best) return null;
  const info = best.p.imageinfo[0], meta = info.extmetadata || {};
  const artist = stripHtml(meta.Artist?.value) || "Wikimedia Commons contributor";
  const license = stripHtml(meta.LicenseShortName?.value);
  return {
    kind: "photo",
    src: info.thumburl || info.url,
    source: "Wikimedia Commons",
    credit: `${artist}${license ? `, ${license}` : ""}`,
    link: info.descriptionurl,
    distanceKm: best.dist,
    date: stripHtml(meta.DateTimeOriginal?.value).slice(0, 10),
  };
}

// ------------------------------------------------------------------ satellite
/** ~6 km wide top-down view from Esri World Imagery (no key; attribution required). */
function satellite(at) {
  const halfKm = 3, aspect = 16 / 9;
  const dLat = halfKm / 111.32 / aspect;
  const dLon = halfKm / (111.32 * Math.max(0.05, Math.cos(at.lat * rad)));
  const bbox = [at.lon - dLon, Math.max(-85, at.lat - dLat), at.lon + dLon, Math.min(85, at.lat + dLat)].map((v) => v.toFixed(5)).join(",");
  const q = new URLSearchParams({ bbox, bboxSR: "4326", imageSR: "3857", size: "640,360", format: "jpg", f: "image" });
  return {
    kind: "photo",
    src: `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?${q}`,
    source: "Satellite",
    credit: "Esri, Maxar, Earthstar Geographics",
    link: `https://www.google.com/maps/@${at.lat.toFixed(5)},${at.lon.toFixed(5)},6000m/data=!3m1!1e3`,
    distanceKm: 0,
    date: "",
  };
}
