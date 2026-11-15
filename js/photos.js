// Images of any Earth location, looked up by latitude/longitude at runtime.
//
// Ground-level image, first source with coverage wins:
//   1. Google Street View (needs CONFIG.googleMapsKey). The metadata request is
//      free and says whether a panorama exists; only then is an image loaded.
//   2. Mapillary street-level photos (needs CONFIG.mapillaryToken).
//   3. Wikimedia Commons photos geotagged within 10 km (no key).
// Satellite view (always available): Esri World Imagery, centred on the point.
//
// Results are cached per coordinate, so re-ranking never refetches.

import { CONFIG } from "./config.js";

const cache = new Map();
let googleDenied = false;   // key rejected or API not enabled: stop asking for this session
let mapsJs = null;          // Maps JavaScript API loader (fallback when metadata is blocked by CORS)

const km = (a, b) => {
  const R = 6371, rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
};
const withTimeout = (p, ms = 8000) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), ms))]);
const getJSON = async (url) => {
  const r = await withTimeout(fetch(url));
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
};
const stripHtml = (s) => (s || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim();

export function photosAvailable() { return true; }

/**
 * @param {number} lat
 * @param {number} lon
 * @returns {Promise<{ ground: Image | null, satellite: Image }>}
 *   Image = { src, source, credit, link, distanceKm }
 */
export function imagesFor(lat, lon) {
  const key = `${lat.toFixed(4)},${lon.toFixed(4)}`;
  if (!cache.has(key)) {
    const at = { lat, lon };
    cache.set(key, (async () => {
      let ground = null;
      for (const find of [streetView, mapillary, commons]) {
        try { ground = await find(at); } catch { ground = null; }
        if (ground) break;
      }
      return { ground, satellite: satellite(at) };
    })());
  }
  return cache.get(key);
}

// ------------------------------------------------------------ Google Street View
const GOOGLE_RADII_M = [2_000, 50_000];

async function streetView(at) {
  const key = CONFIG.googleMapsKey;
  if (!key || googleDenied) return null;
  for (const radius of GOOGLE_RADII_M) {
    const pano = await panoramaNear(at, radius, key);
    if (pano === "denied") { googleDenied = true; return null; }
    if (!pano) continue;
    const q = new URLSearchParams({ size: "640x360", pano: pano.id, fov: "90", pitch: "0", key });
    return {
      src: `https://maps.googleapis.com/maps/api/streetview?${q}`,
      source: "Google Street View",
      credit: pano.copyright || "© Google",
      link: `https://www.google.com/maps/@?api=1&map_action=pano&pano=${encodeURIComponent(pano.id)}`,
      distanceKm: km(at, pano.location),
      date: pano.date || "",
    };
  }
  return null;
}

/** Nearest outdoor panorama within `radius` m: { id, location, date, copyright }, null, or "denied". */
async function panoramaNear(at, radius, key) {
  const q = new URLSearchParams({ location: `${at.lat},${at.lon}`, radius: String(radius), source: "outdoor", key });
  let meta;
  try {
    meta = await getJSON(`https://maps.googleapis.com/maps/api/streetview/metadata?${q}`);
  } catch {
    // The metadata endpoint can be blocked by CORS in some browsers; ask the Maps JavaScript API instead.
    return panoramaViaMapsJs(at, radius, key);
  }
  if (meta.status === "OK") return { id: meta.pano_id, location: { lat: meta.location.lat, lon: meta.location.lng }, date: meta.date, copyright: meta.copyright };
  if (meta.status === "REQUEST_DENIED" || meta.status === "OVER_QUERY_LIMIT") return "denied";
  return null;
}

function loadMapsJs(key) {
  if (window.google?.maps?.StreetViewService) return Promise.resolve(window.google.maps);
  if (!mapsJs) {
    mapsJs = new Promise((resolve, reject) => {
      const cb = `__mapsReady${Date.now()}`;
      window[cb] = () => { delete window[cb]; resolve(window.google.maps); };
      window.gm_authFailure = () => { googleDenied = true; };
      const s = document.createElement("script");
      s.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&loading=async&callback=${cb}`;
      s.async = true;
      s.onerror = () => reject(new Error("Maps JavaScript API failed to load"));
      document.head.appendChild(s);
    });
  }
  return withTimeout(mapsJs, 10_000);
}

async function panoramaViaMapsJs(at, radius, key) {
  const maps = await loadMapsJs(key);
  try {
    const { data } = await new maps.StreetViewService().getPanorama({
      location: { lat: at.lat, lng: at.lon }, radius,
      source: maps.StreetViewSource.OUTDOOR, preference: maps.StreetViewPreference.NEAREST,
    });
    const ll = data.location.latLng;
    return { id: data.location.pano, location: { lat: ll.lat(), lon: ll.lng() }, date: data.imageDate, copyright: data.copyright };
  } catch (err) {
    if (googleDenied || /REQUEST_DENIED/.test(String(err?.code || err))) return "denied";
    return null;   // ZERO_RESULTS
  }
}

// ------------------------------------------------------------------ Mapillary
async function mapillary(at) {
  const token = CONFIG.mapillaryToken;
  if (!token) return null;
  // Mapillary limits bbox size, so search a ~10 km box and pick the closest image.
  const d = 0.05, dl = d / Math.max(0.2, Math.cos(at.lat * Math.PI / 180));
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
  const dLon = halfKm / (111.32 * Math.max(0.05, Math.cos(at.lat * Math.PI / 180)));
  const bbox = [at.lon - dLon, Math.max(-85, at.lat - dLat), at.lon + dLon, Math.min(85, at.lat + dLat)].map((v) => v.toFixed(5)).join(",");
  const q = new URLSearchParams({ bbox, bboxSR: "4326", imageSR: "3857", size: "640,360", format: "jpg", f: "image" });
  return {
    src: `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?${q}`,
    source: "Satellite",
    credit: "Esri, Maxar, Earthstar Geographics",
    link: `https://www.google.com/maps/@${at.lat.toFixed(5)},${at.lon.toFixed(5)},6000m/data=!3m1!1e3`,
    distanceKm: 0,
    date: "",
  };
}
