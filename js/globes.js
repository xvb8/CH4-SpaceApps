// CesiumJS globes: a Mars target picker and an Earth score map with
// extruded bars for every tested location.

import { CONFIG } from "./config.js";
import { marsTextureCanvas } from "./mars-texture.js";
import { rampColor, cellIndex, scoreField } from "./score-field.js";

const C = () => window.Cesium;

// Camera altitudes for the Earth view; both keep the whole disc in frame.
const EARTH_OVERVIEW_M = 26_000_000;
const EARTH_VIEW_M = 20_000_000;

export function cesiumAvailable() {
  return typeof window.Cesium !== "undefined";
}

export function initIon() {
  if (!cesiumAvailable()) return;
  C().Ion.defaultAccessToken = CONFIG.cesiumIonToken;
}

const BASE_OPTIONS = () => ({
  animation: false,
  timeline: false,
  baseLayerPicker: false,
  geocoder: false,
  homeButton: false,
  sceneModePicker: false,
  navigationHelpButton: false,
  fullscreenButton: false,
  infoBox: false,
  selectionIndicator: false,
  skyBox: false,
  contextOptions: { webgl: { alpha: true } },
  msaaSamples: 4,
});

/** Rotate the camera slowly until the user interacts; resume after idle. */
function autoRotate(viewer, speed = 0.0009) {
  const Cs = C();
  let lastInput = -Infinity;
  const handler = new Cs.ScreenSpaceEventHandler(viewer.scene.canvas);
  const touch = () => { lastInput = performance.now(); };
  [Cs.ScreenSpaceEventType.LEFT_DOWN, Cs.ScreenSpaceEventType.RIGHT_DOWN, Cs.ScreenSpaceEventType.MIDDLE_DOWN,
   Cs.ScreenSpaceEventType.WHEEL, Cs.ScreenSpaceEventType.PINCH_START].forEach((t) => handler.setInputAction(touch, t));
  const state = { enabled: true, pause: () => touch() };
  viewer.clock.onTick.addEventListener(() => {
    if (state.enabled && performance.now() - lastInput > 9000) {
      viewer.scene.camera.rotate(Cs.Cartesian3.UNIT_Z, -speed);
    }
  });
  return state;
}

/** Only render while the viewer is on screen. */
function renderWhenVisible(viewer, el) {
  if (!("IntersectionObserver" in window)) return;
  new IntersectionObserver(([entry]) => {
    viewer.useDefaultRenderLoop = entry.isIntersecting;
  }, { rootMargin: "120px" }).observe(el);
}

// ===================================================================== MARS

/**
 * Create the Mars viewer.
 * @param {HTMLElement} el
 * @param {{ regions: Array, onPick: (lat:number, lon:number) => void, onStatus: (msg:string) => void, onHover?: (ll: {lat:number, lon:number}|null, pos?: {x:number, y:number}) => void }} opts
 */
export async function createMarsViewer(el, { regions, onPick, onStatus, onHover }) {
  const Cs = C();
  const MARS = Cs.Ellipsoid.MARS;
  const texture = marsTextureCanvas().toDataURL("image/jpeg", 0.92);
  const viewer = new Cs.Viewer(el, {
    ...BASE_OPTIONS(),
    ellipsoid: MARS,
    baseLayer: Cs.ImageryLayer.fromProviderAsync(Cs.SingleTileImageryProvider.fromUrl(texture, { ellipsoid: MARS })),
    skyAtmosphere: new Cs.SkyAtmosphere(MARS),
  });
  const scene = viewer.scene;
  scene.backgroundColor = Cs.Color.TRANSPARENT;
  scene.globe.showGroundAtmosphere = false;
  scene.globe.baseColor = Cs.Color.fromCssColorString("#7a3018");
  scene.fog.enabled = false;
  // Dusty butterscotch sky glow instead of Earth blue.
  scene.skyAtmosphere.hueShift = -0.52;
  scene.skyAtmosphere.saturationShift = -0.1;
  scene.skyAtmosphere.brightnessShift = -0.15;
  scene.screenSpaceCameraController.minimumZoomDistance = 60_000;
  scene.screenSpaceCameraController.maximumZoomDistance = 40_000_000;
  viewer.camera.setView({ destination: Cs.Cartesian3.fromDegrees(77, 18, 13_000_000, MARS) });

  let tileset = null;
  let source = "Mars";
  if (CONFIG.marsIonAssetId) {
    try {
      tileset = await Cs.Cesium3DTileset.fromIonAssetId(CONFIG.marsIonAssetId, { ellipsoid: MARS, enableCollision: true });
      scene.primitives.add(tileset);
      scene.globe.show = false;
      source = "Mars, Cesium ion";
    } catch (err) {
      console.warn("Mars 3D Tiles unavailable, using procedural globe:", err);
    }
  }
  onStatus?.(source);

  // Anchor regions
  const LABEL_FONT = "600 14px 'Noto Sans', sans-serif";
  for (const r of regions) {
    viewer.entities.add({
      position: Cs.Cartesian3.fromDegrees(r.lon, r.lat, 30_000, MARS),
      point: { pixelSize: 4, color: Cs.Color.WHITE.withAlpha(0.9), outlineColor: Cs.Color.BLACK.withAlpha(0.6), outlineWidth: 1 },
      label: {
        text: r.name, font: LABEL_FONT, fillColor: Cs.Color.WHITE,
        outlineColor: Cs.Color.BLACK.withAlpha(0.75), outlineWidth: 3, style: Cs.LabelStyle.FILL_AND_OUTLINE,
        horizontalOrigin: Cs.HorizontalOrigin.LEFT, pixelOffset: new Cs.Cartesian2(8, 0),
        distanceDisplayCondition: new Cs.DistanceDisplayCondition(0, 9_000_000),
        showBackground: false,
      },
    });
  }

  // Target marker
  const target = viewer.entities.add({
    show: false,
    position: Cs.Cartesian3.fromDegrees(0, 0, 40_000, MARS),
    point: { pixelSize: 10, color: Cs.Color.TRANSPARENT, outlineColor: Cs.Color.WHITE, outlineWidth: 2 },
    label: {
      text: "TARGET", font: LABEL_FONT, fillColor: Cs.Color.WHITE,
      pixelOffset: new Cs.Cartesian2(0, -24),
      showBackground: true,
      backgroundColor: Cs.Color.fromCssColorString("#03050a").withAlpha(0.88),
      backgroundPadding: new Cs.Cartesian2(7, 4),
    },
  });

  const rotation = autoRotate(viewer, 0.0007);
  const handler = new Cs.ScreenSpaceEventHandler(scene.canvas);
  handler.setInputAction((e) => {
    let cart;
    if (tileset && scene.pickPositionSupported) {
      const picked = scene.pick(e.position);
      if (picked) cart = scene.pickPosition(e.position);
    }
    if (!cart) cart = viewer.camera.pickEllipsoid(e.position, MARS);
    if (!cart) return;
    const carto = MARS.cartesianToCartographic(cart);
    if (!carto) return;
    onPick(Cs.Math.toDegrees(carto.latitude), Cs.Math.toDegrees(carto.longitude));
  }, Cs.ScreenSpaceEventType.LEFT_CLICK);
  handler.setInputAction((e) => {
    const cart = viewer.camera.pickEllipsoid(e.endPosition, MARS);
    const carto = cart && MARS.cartesianToCartographic(cart);
    onHover?.(carto ? { lat: Cs.Math.toDegrees(carto.latitude), lon: Cs.Math.toDegrees(carto.longitude) } : null, e.endPosition);
  }, Cs.ScreenSpaceEventType.MOUSE_MOVE);
  scene.canvas.addEventListener("pointerleave", () => onHover?.(null));

  renderWhenVisible(viewer, el);

  return {
    viewer,
    source,
    setTarget(lat, lon, fly = true) {
      target.position = Cs.Cartesian3.fromDegrees(lon, lat, 40_000, MARS);
      target.show = true;
      rotation.pause();
      if (fly) {
        // ~11,000 km keeps the whole disc in view while centring the target.
        viewer.camera.flyTo({ destination: Cs.Cartesian3.fromDegrees(lon, lat, 11_000_000, MARS), duration: 1.8 });
      }
    },
  };
}

// ==================================================================== EARTH

export async function createEarthViewer(el, { coastlines = null, gridStep = 2.5, onHover, onPick }) {
  const Cs = C();
  const viewer = new Cs.Viewer(el, { ...BASE_OPTIONS(), baseLayer: false });
  const scene = viewer.scene;
  scene.backgroundColor = Cs.Color.TRANSPARENT;
  scene.globe.baseColor = Cs.Color.fromCssColorString("#0b1638");
  scene.screenSpaceCameraController.minimumZoomDistance = 200_000;
  scene.screenSpaceCameraController.maximumZoomDistance = 45_000_000;
  scene.skyAtmosphere.brightnessShift = 0.05;

  const addFallbackImagery = async () => {
    try {
      const provider = await Cs.TileMapServiceImageryProvider.fromUrl(Cs.buildModuleUrl("Assets/Textures/NaturalEarthII"));
      viewer.imageryLayers.addImageryProvider(provider, 0);
    } catch (err) {
      console.error("Fallback imagery failed", err);
    }
  };
  let imagery = "Cesium ion World Imagery";
  try {
    const layer = Cs.ImageryLayer.fromWorldImagery();
    layer.errorEvent.addEventListener(() => { imagery = "Natural Earth II"; addFallbackImagery(); });
    viewer.imageryLayers.add(layer);
  } catch {
    imagery = "Natural Earth II";
    await addFallbackImagery();
  }

  viewer.camera.setView({ destination: Cs.Cartesian3.fromDegrees(-40, 15, EARTH_OVERVIEW_M) });
  const rotation = autoRotate(viewer, 0.0008);
  renderWhenVisible(viewer, el);

  let barPrimitive = null;
  let barPoints = [];
  let mode = "bars";
  let cellAt = () => null;
  let fieldLayer = null, fieldToken = 0;
  const markers = new Cs.CustomDataSource("top5");
  viewer.dataSources.add(markers);

  // Hover / click on bars
  const handler = new Cs.ScreenSpaceEventHandler(scene.canvas);
  let hoverIdx = -1;
  handler.setInputAction((e) => {
    const picked = scene.pick(e.endPosition);
    const idx = picked && picked.id && picked.id.kind === "bar" ? picked.id.index : -1;
    if (idx !== hoverIdx) hoverIdx = idx;
    onHover?.(idx >= 0 ? barPoints[idx] : cellUnder(e.endPosition), e.endPosition);
  }, Cs.ScreenSpaceEventType.MOUSE_MOVE);
  handler.setInputAction((e) => {
    const picked = scene.pick(e.position);
    if (picked && picked.id) {
      if (picked.id.kind === "bar") onPick?.(barPoints[picked.id.index]);
      else if (picked.id.properties?.locId) onPick?.({ id: picked.id.properties.locId.getValue() });
    } else {
      const cell = cellUnder(e.position);
      if (cell) onPick?.(cell);
    }
  }, Cs.ScreenSpaceEventType.LEFT_CLICK);

  // Color map: the grid point whose cell is under the pointer (the draped field itself is not pickable).
  function cellUnder(pos) {
    if (mode !== "color") return null;
    const cart = viewer.camera.pickEllipsoid(pos);
    if (!cart) return null;
    const carto = Cs.Cartographic.fromCartesian(cart);
    return cellAt(Cs.Math.toDegrees(carto.latitude), Cs.Math.toDegrees(carto.longitude));
  }

  /** Drape the smooth score field as one global imagery tile; replaces the previous one once loaded. */
  async function setField(bars) {
    const token = ++fieldToken;
    const drop = () => { if (fieldLayer) { viewer.imageryLayers.remove(fieldLayer, true); fieldLayer = null; } };
    if (!bars) { drop(); return; }
    const { canvas } = scoreField(bars, gridStep, coastlines, { width: 2048, height: 1024 });
    const provider = await Cs.SingleTileImageryProvider.fromUrl(canvas.toDataURL("image/png"));
    if (token !== fieldToken) return;   // superseded by a newer call
    drop();
    fieldLayer = viewer.imageryLayers.addImageryProvider(provider);
    scene.requestRender();
  }

  const api = {
    viewer,
    get imagery() { return imagery; },

    /** Map style: "bars" (extruded boxes) or "color" (smooth field draped on the globe). Applies on the next setBars. */
    setMode(m) { mode = m === "color" ? "color" : "bars"; },

    /**
     * Draw every point as an extruded bar, or in "color" mode drape a smooth
     * score field and keep only the named sites as short markers.
     * @param {Array} points  locations with lat/lon
     * @param {(p) => number} valueOf  score accessor
     */
    setBars(points, valueOf) {
      const all = points.map((p) => ({ p, v: valueOf(p) })).filter((d) => d.v != null);
      barPoints = all.map((d) => d.p);
      const vals = all.map((d) => d.v);
      const min = Math.min(...vals), max = Math.max(...vals);
      const span = max - min || 1;
      const ts = vals.map((v) => (v - min) / span);
      cellAt = cellIndex(barPoints, gridStep);
      setField(mode === "color" ? barPoints.map((p, i) => ({ p, t: ts[i] })) : null);
      const instances = [];
      barPoints.forEach((p, i) => {
        if (mode === "color" && p.kind !== "site") return;
        const t = ts[i];
        const [r, g, b] = rampColor(t);
        const color = Cs.ColorGeometryInstanceAttribute.fromColor(new Cs.Color(r / 255, g / 255, b / 255, 0.95));
        // Bars mode, and named sites in color mode (as short markers).
        const height = mode === "color" ? 90_000 : CONFIG.barMinHeightMeters + t ** 1.6 * (CONFIG.barMaxHeightMeters - CONFIG.barMinHeightMeters);
        const width = p.kind === "site" ? CONFIG.barWidthMeters * 1.25 : CONFIG.barWidthMeters;
        const enu = Cs.Transforms.eastNorthUpToFixedFrame(Cs.Cartesian3.fromDegrees(p.lon, p.lat, 0));
        const modelMatrix = Cs.Matrix4.multiplyByTranslation(enu, new Cs.Cartesian3(0, 0, height / 2), new Cs.Matrix4());
        instances.push(new Cs.GeometryInstance({
          geometry: Cs.BoxGeometry.fromDimensions({
            vertexFormat: Cs.PerInstanceColorAppearance.VERTEX_FORMAT,
            dimensions: new Cs.Cartesian3(width, width, height),
          }),
          modelMatrix,
          id: { kind: "bar", index: i },
          attributes: { color },
        }));
      });
      const next = new Cs.Primitive({
        geometryInstances: instances,
        appearance: new Cs.PerInstanceColorAppearance({ translucent: true, closed: true }),
        asynchronous: true,
      });
      scene.primitives.add(next);
      // Swap once the new bars are ready so the globe never flashes empty.
      const prev = barPrimitive;
      barPrimitive = next;
      if (prev) {
        const remove = scene.postRender.addEventListener(() => {
          if (next.ready || next.isDestroyed()) { scene.primitives.remove(prev); remove(); }
        });
      }
      return { min, max };
    },

    /** Labeled markers for the top analogs. */
    setTopMarkers(top) {
      markers.entities.removeAll();
      top.forEach((s, i) => {
        markers.entities.add({
          position: Cs.Cartesian3.fromDegrees(s.lon, s.lat, CONFIG.barMaxHeightMeters + 120_000),
          properties: { locId: s.id },
          point: { pixelSize: 8, color: Cs.Color.WHITE, outlineColor: Cs.Color.fromCssColorString("#03050a"), outlineWidth: 1 },
          label: {
            text: `${String(i + 1).padStart(2, "0")}  ${s.name.split(",")[0]}`,
            font: "700 14px 'Noto Sans', sans-serif",
            fillColor: Cs.Color.WHITE,
            outlineColor: Cs.Color.BLACK.withAlpha(0.85), outlineWidth: 4, style: Cs.LabelStyle.FILL_AND_OUTLINE,
            pixelOffset: new Cs.Cartesian2(0, -18),
          },
          polyline: {
            positions: [Cs.Cartesian3.fromDegrees(s.lon, s.lat, 0), Cs.Cartesian3.fromDegrees(s.lon, s.lat, CONFIG.barMaxHeightMeters + 120_000)],
            width: 1,
            material: Cs.Color.WHITE.withAlpha(0.55),
          },
        });
      });
    },

    flyTo(lat, lon) {
      rotation.pause();
      // Stay far enough out that the whole disc remains in view.
      const back = Math.max(-70, Math.min(70, lat - 18));
      viewer.camera.flyTo({
        destination: Cs.Cartesian3.fromDegrees(lon, back, EARTH_VIEW_M),
        duration: 2.2,
        easingFunction: Cs.EasingFunction.CUBIC_IN_OUT,
      });
    },

    overview() {
      viewer.camera.flyTo({ destination: Cs.Cartesian3.fromDegrees(-40, 15, EARTH_OVERVIEW_M), duration: 1.6 });
    },
  };
  return api;
}
