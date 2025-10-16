// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/photoguessr";
import topbar from "../vendor/topbar";

const TILE_SIZE = 256;
const MIN_LAT = -85.05112878;
const MAX_LAT = 85.05112878;
const MIN_ZOOM = 2;
const MAX_ZOOM = 18;
const DEFAULT_CENTER = { lat: 20, lng: 0 };

class OSMView {
  constructor(element, options = {}) {
    this.el = element;
    this.mode = options.mode || "submission";
    this.playerId = options.playerId || null;
    this.zoom = clampZoom(options.zoom ?? 2);
    this.marker = options.marker ?? null;
    this.actual = options.actual ?? null;
    this.guesses = Array.isArray(options.guesses) ? options.guesses : [];
    this.showControls = options.controls !== false;
    this.userHasInteracted = false;
    this.wheelAccumulator = 0;
    this.onSelect = null;
    this.dragState = null;
    this.viewport = null;
    this.rafId = null;

    this.center = clampLatLng(
      options.center || this.marker || this.actual || DEFAULT_CENTER,
    );

    this.el.classList.add("osm-root");
    const style = getComputedStyle(this.el);
    if (style.position === "static") {
      this.el.style.position = "relative";
    }
    this.el.style.backgroundColor ||= "rgb(4 13 33)";
    this.el.style.touchAction = "none";

    this.tileLayer = document.createElement("div");
    this.tileLayer.className = "osm-tile-layer";

    this.markerLayer = document.createElement("div");
    this.markerLayer.className = "osm-marker-layer";

    this.controls = this.createControls();
    this.attribution = this.createAttribution();

    this.el.innerHTML = "";
    this.el.append(
      this.tileLayer,
      this.markerLayer,
      this.controls,
      this.attribution,
    );
    this.updateControlsVisibility();

    this.pointerDownHandler = (event) => this.handlePointerDown(event);
    this.pointerMoveHandler = (event) => this.handlePointerMove(event);
    this.pointerUpHandler = (event) => this.handlePointerUp(event);
    this.pointerCancelHandler = (event) => this.handlePointerUp(event);
    this.wheelHandler = (event) => this.handleWheel(event);
    this.doubleClickHandler = (event) => this.handleDoubleClick(event);

    this.el.addEventListener("pointerdown", this.pointerDownHandler);
    this.el.addEventListener("pointermove", this.pointerMoveHandler);
    this.el.addEventListener("pointerup", this.pointerUpHandler);
    this.el.addEventListener("pointercancel", this.pointerCancelHandler);
    this.el.addEventListener("wheel", this.wheelHandler, { passive: false });
    this.el.addEventListener("dblclick", this.doubleClickHandler);

    if (typeof ResizeObserver !== "undefined") {
      this.resizeObserver = new ResizeObserver(() => this.render());
      this.resizeObserver.observe(this.el);
    }

    this.render();
  }

  createControls() {
    const wrapper = document.createElement("div");
    wrapper.className = "osm-controls";

    const zoomIn = document.createElement("button");
    zoomIn.type = "button";
    zoomIn.className = "osm-control-btn";
    zoomIn.textContent = "+";
    zoomIn.setAttribute("aria-label", "Zoom in");
    zoomIn.addEventListener("click", () => {
      this.userHasInteracted = true;
      this.wheelAccumulator = 0;
      this.adjustZoom(1);
    });

    const zoomOut = document.createElement("button");
    zoomOut.type = "button";
    zoomOut.className = "osm-control-btn";
    zoomOut.textContent = "-";
    zoomOut.setAttribute("aria-label", "Zoom out");
    zoomOut.addEventListener("click", () => {
      this.userHasInteracted = true;
      this.wheelAccumulator = 0;
      this.adjustZoom(-1);
    });

    const stopPropagation = (event) => {
      event.stopPropagation();
    };
    zoomIn.addEventListener("pointerdown", stopPropagation);
    zoomIn.addEventListener("pointerup", stopPropagation);
    zoomOut.addEventListener("pointerdown", stopPropagation);
    zoomOut.addEventListener("pointerup", stopPropagation);

    wrapper.append(zoomIn, zoomOut);
    return wrapper;
  }

  createAttribution() {
    const attribution = document.createElement("div");
    attribution.className = "osm-attribution";
    attribution.innerHTML =
      '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a> contributors';
    return attribution;
  }

  updateControlsVisibility() {
    this.controls.style.display = this.showControls ? "flex" : "none";
  }

  setSelectHandler(callback) {
    this.onSelect = callback;
  }

  update(options = {}) {
    const modeChanged = options.mode && options.mode !== this.mode;
    if (modeChanged) {
      this.mode = options.mode;
      this.userHasInteracted = false;
    } else if (options.mode) {
      this.mode = options.mode;
    }

    if (options.playerId !== undefined) {
      this.playerId = options.playerId;
    }

    if (typeof options.zoom === "number" && Number.isFinite(options.zoom)) {
      const nextZoom = clampZoom(options.zoom);
      if (
        nextZoom !== this.zoom &&
        (!this.userHasInteracted || modeChanged)
      ) {
        this.zoom = nextZoom;
      }
    }

    if ("marker" in options) {
      this.marker = options.marker;
    }

    if ("actual" in options) {
      this.actual = options.actual;
    }

    if ("guesses" in options) {
      this.guesses = Array.isArray(options.guesses) ? options.guesses : [];
    }

    if ("controls" in options) {
      this.showControls = options.controls !== false;
      this.updateControlsVisibility();
    }

    if (options.center && (!this.userHasInteracted || modeChanged)) {
      this.center = clampLatLng(options.center);
    }

    this.render();
  }

  destroy() {
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }

    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
    }

    this.el.removeEventListener("pointerdown", this.pointerDownHandler);
    this.el.removeEventListener("pointermove", this.pointerMoveHandler);
    this.el.removeEventListener("pointerup", this.pointerUpHandler);
    this.el.removeEventListener("pointercancel", this.pointerCancelHandler);
    this.el.removeEventListener("wheel", this.wheelHandler);
    this.el.removeEventListener("dblclick", this.doubleClickHandler);

    this.tileLayer.remove();
    this.markerLayer.remove();
    this.controls.remove();
    this.attribution.remove();
    this.el.classList.remove("osm-root", "is-dragging");
    this.el.textContent = "";
  }

  handlePointerDown(event) {
    if (event.button !== 0) return;
    if (
      event.target.closest(".osm-controls") ||
      event.target.closest(".osm-attribution")
    ) {
      return;
    }
    this.el.setPointerCapture(event.pointerId);
    this.dragState = {
      id: event.pointerId,
      origin: { x: event.clientX, y: event.clientY },
      centerSnapshot: { ...this.center },
      moved: false,
    };
    this.el.classList.add("is-dragging");
  }

  handlePointerMove(event) {
    if (!this.dragState || event.pointerId !== this.dragState.id) return;

    const dx = event.clientX - this.dragState.origin.x;
    const dy = event.clientY - this.dragState.origin.y;

    if (!this.dragState.moved && (Math.abs(dx) > 2 || Math.abs(dy) > 2)) {
      this.dragState.moved = true;
    }

    if (!this.dragState.moved) return;

    this.userHasInteracted = true;

    const startPoint = latLngToPoint(
      this.dragState.centerSnapshot.lat,
      this.dragState.centerSnapshot.lng,
      this.zoom,
    );
    const targetPoint = { x: startPoint.x - dx, y: startPoint.y - dy };
    this.center = clampLatLng(
      pointToLatLng(targetPoint.x, targetPoint.y, this.zoom),
    );
    this.render();
  }

  handlePointerUp(event) {
    if (!this.dragState || event.pointerId !== this.dragState.id) return;
    this.el.releasePointerCapture(event.pointerId);

    const moved = this.dragState.moved;
    const { clientX, clientY } = event;
    this.dragState = null;
    this.el.classList.remove("is-dragging");

    if (!moved && this.onSelect && this.mode !== "reveal") {
      const coords = this.cursorToLatLng(clientX, clientY);
      if (coords) {
        this.userHasInteracted = true;
        this.onSelect({
          lat: Number(coords.lat.toFixed(6)),
          lng: Number(coords.lng.toFixed(6)),
        });
      }
    }
  }

  handleWheel(event) {
    event.preventDefault();
    const rect = this.el.getBoundingClientRect();
    const focus = {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };

    this.userHasInteracted = true;
    const delta = normalizeWheelDelta(event);
    if (delta === 0) return;

    this.wheelAccumulator += delta;
    const maxStepsPerFrame = 4;
    let steps = 0;

    while (Math.abs(this.wheelAccumulator) >= 1 && steps < maxStepsPerFrame) {
      const step = this.wheelAccumulator > 0 ? -1 : 1;
      const adjusted = this.adjustZoom(step, focus);
      if (!adjusted) {
        this.wheelAccumulator = 0;
        break;
      }
      this.wheelAccumulator -= step;
      steps += 1;
    }
  }

  handleDoubleClick(event) {
    event.preventDefault();
    const rect = this.el.getBoundingClientRect();
    const focus = {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };

    this.userHasInteracted = true;
    this.wheelAccumulator = 0;
    const delta = event.shiftKey ? -1 : 1;
    this.adjustZoom(delta, focus);
  }

  adjustZoom(delta, focusPoint) {
    const targetZoom = clampZoom(this.zoom + delta);
    if (targetZoom === this.zoom) return false;

    const rect = this.el.getBoundingClientRect();
    const viewport = this.buildViewport(rect.width, rect.height);
    const focus = focusPoint || { x: rect.width / 2, y: rect.height / 2 };
    const worldX = viewport.topLeftX + focus.x;
    const worldY = viewport.topLeftY + focus.y;
    const focusLatLng = pointToLatLng(worldX, worldY, this.zoom);

    this.zoom = targetZoom;

    const newPoint = latLngToPoint(focusLatLng.lat, focusLatLng.lng, this.zoom);
    const newTopLeftX = newPoint.x - focus.x;
    const newTopLeftY = newPoint.y - focus.y;
    const centerPointX = newTopLeftX + rect.width / 2;
    const centerPointY = newTopLeftY + rect.height / 2;

    this.center = clampLatLng(
      pointToLatLng(centerPointX, centerPointY, this.zoom),
    );
    this.render();
    return true;
  }

  cursorToLatLng(clientX, clientY) {
    if (!this.viewport) return null;
    const rect = this.el.getBoundingClientRect();
    const x = clientX - rect.left;
    const y = clientY - rect.top;

    if (x < 0 || y < 0 || x > rect.width || y > rect.height) return null;

    const worldX = this.viewport.topLeftX + x;
    const worldY = this.viewport.topLeftY + y;
    return clampLatLng(pointToLatLng(worldX, worldY, this.zoom));
  }

  buildViewport(width, height) {
    const w = width || this.el.clientWidth || 1;
    const h = height || this.el.clientHeight || 1;
    const centerPoint = latLngToPoint(
      this.center.lat,
      this.center.lng,
      this.zoom,
    );
    const topLeftX = centerPoint.x - w / 2;
    const topLeftY = centerPoint.y - h / 2;
    return { width: w, height: h, topLeftX, topLeftY, centerPoint };
  }

  render() {
    if (this.rafId) {
      cancelAnimationFrame(this.rafId);
    }
    this.rafId = requestAnimationFrame(() => this.renderNow());
  }

  renderNow() {
    this.rafId = null;
    const rect = this.el.getBoundingClientRect();
    const viewport = this.buildViewport(rect.width, rect.height);
    this.viewport = viewport;
    this.renderTiles(viewport);
    this.renderMarkers(viewport);
  }

  renderTiles(viewport) {
    const tilesNeeded = new Set();
    const startX = Math.floor(viewport.topLeftX / TILE_SIZE);
    const endX = Math.floor((viewport.topLeftX + viewport.width) / TILE_SIZE);
    const startY = Math.floor(viewport.topLeftY / TILE_SIZE);
    const endY = Math.floor((viewport.topLeftY + viewport.height) / TILE_SIZE);
    const maxIndex = 2 ** this.zoom;

    for (let x = startX; x <= endX; x += 1) {
      const wrappedX = wrapTileIndex(x, this.zoom);
      for (let y = startY; y <= endY; y += 1) {
        if (y < 0 || y >= maxIndex) continue;

        const left = x * TILE_SIZE - viewport.topLeftX;
        const top = y * TILE_SIZE - viewport.topLeftY;
        const key = `${this.zoom}-${wrappedX}-${y}`;
        tilesNeeded.add(key);

        let tile = this.tileLayer.querySelector(`[data-key="${key}"]`);
        if (!tile) {
          tile = document.createElement("img");
          tile.dataset.key = key;
          tile.className = "osm-tile";
          tile.alt = "";
          tile.decoding = "async";
          tile.loading = "lazy";
          tile.draggable = false;
          tile.src = tileUrl(this.zoom, wrappedX, y);
          this.tileLayer.appendChild(tile);
        }

        tile.style.transform = `translate(${left}px, ${top}px)`;
      }
    }

    Array.from(this.tileLayer.children).forEach((node) => {
      if (!tilesNeeded.has(node.dataset.key)) {
        node.remove();
      }
    });
  }

  renderMarkers(viewport) {
    this.markerLayer.innerHTML = "";

    const markers = [];

    if (this.mode === "reveal") {
      if (isFiniteLatLng(this.actual)) {
        markers.push({
          lat: this.actual.lat,
          lng: this.actual.lng,
          type: "actual",
          title: "Actual location",
          label: "Actual",
        });
      }

      this.guesses
        .filter((guess) => isFiniteLatLng(guess))
        .forEach((guess) => {
          const isCurrentPlayer =
            this.playerId && guess.player_id === this.playerId;
          const hasPoints = Number.isFinite(guess.points);

          markers.push({
            lat: guess.lat,
            lng: guess.lng,
            type: isCurrentPlayer ? "self" : "other",
            title: guess.player_name
              ? `${guess.player_name}${hasPoints ? ` • ${guess.points} pts` : ""}`
              : undefined,
            label: hasPoints ? `${guess.points} pts` : undefined,
          });
        });
    } else if (isFiniteLatLng(this.marker)) {
      markers.push({
        lat: this.marker.lat,
        lng: this.marker.lng,
        type: this.mode === "guess" ? "self" : "primary",
        title: this.mode === "guess" ? "Your guess" : "Selected location",
      });
    }

    markers.forEach((marker) => {
      const point = latLngToPoint(marker.lat, marker.lng, this.zoom);
      const left = point.x - viewport.topLeftX;
      const top = point.y - viewport.topLeftY;

      if (
        left < -60 ||
        left > viewport.width + 60 ||
        top < -60 ||
        top > viewport.height + 60
      ) {
        return;
      }

      const markerEl = document.createElement("div");
      markerEl.className = `osm-marker osm-marker--${marker.type}`;
      markerEl.style.left = `${left}px`;
      markerEl.style.top = `${top}px`;
      if (marker.title) {
        markerEl.title = marker.title;
      }

      if (marker.label) {
        const label = document.createElement("span");
        label.className = "osm-marker__label";
        label.textContent = marker.label;
        markerEl.appendChild(label);
      }

      this.markerLayer.appendChild(markerEl);
    });
  }
}

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
const clampZoom = (value) => clamp(Math.round(value), MIN_ZOOM, MAX_ZOOM);

const clampLatLng = (coords) => {
  if (!coords) return null;
  return {
    lat: clamp(coords.lat, MIN_LAT, MAX_LAT),
    lng: normalizeLng(coords.lng),
  };
};

const normalizeWheelDelta = (event) => {
  let delta = event.deltaY;
  if (event.deltaMode === 1) {
    delta *= 20;
  } else if (event.deltaMode === 2) {
    delta *= 60;
  }
  return delta / 240;
};

const normalizeLng = (lng) => {
  const normalized = ((((lng + 180) % 360) + 360) % 360) - 180;
  return Number.isFinite(normalized) ? normalized : 0;
};

const latLngToPoint = (lat, lng, zoom) => {
  const clampedLat = clamp(lat, MIN_LAT, MAX_LAT);
  const latRad = (clampedLat * Math.PI) / 180;
  const sinLat = Math.sin(latRad);
  const scale = TILE_SIZE * 2 ** zoom;

  const x = ((normalizeLng(lng) + 180) / 360) * scale;
  const y =
    (0.5 - Math.log((1 + sinLat) / (1 - sinLat)) / (4 * Math.PI)) * scale;

  return { x, y };
};

const pointToLatLng = (x, y, zoom) => {
  const scale = TILE_SIZE * 2 ** zoom;
  const lng = (x / scale) * 360 - 180;
  const n = Math.PI - (2 * Math.PI * y) / scale;
  const lat = (180 / Math.PI) * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)));

  return {
    lat: clamp(lat, MIN_LAT, MAX_LAT),
    lng: normalizeLng(lng),
  };
};

const wrapTileIndex = (value, zoom) => {
  const max = 2 ** zoom;
  return ((value % max) + max) % max;
};

const tileUrl = (zoom, x, y) =>
  `https://tile.openstreetmap.org/${zoom}/${x}/${y}.png`;

const parseLatLng = (latValue, lngValue) => {
  const lat = parseNumber(latValue);
  const lng = parseNumber(lngValue);
  if (lat === null || lng === null) return null;
  return { lat, lng };
};

const parseZoom = (value, fallback) => {
  const parsed = parseNumber(value);
  return parsed === null ? fallback : clampZoom(parsed);
};

const parseBoolean = (value, fallback) => {
  if (value === undefined) return fallback;
  if (value === "false" || value === "0") return false;
  if (value === "true" || value === "1") return true;
  return fallback;
};

const parseNumber = (value) => {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number.parseFloat(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
};

const parseGuesses = (value) =>
  parseJson(value).map((guess) => ({
    ...guess,
    lat: parseNumber(guess.lat),
    lng: parseNumber(guess.lng),
  }));

const isFiniteLatLng = (coords) =>
  coords && Number.isFinite(coords.lat) && Number.isFinite(coords.lng);

const hooks = {
  ...colocatedHooks,

  WorldMap: {
    mounted() {
      const options = this.extractOptions();
      if (options.zoom === undefined) {
        options.zoom = 2;
      }
      this.map = new OSMView(this.el, options);
      this.map.setSelectHandler((coords) => {
        if (this.map.mode === "submission") {
          this.pushEvent("set_submission_location", coords);
        } else if (this.map.mode === "guess") {
          this.pushEvent("set_guess_location", coords);
        }
      });
    },

    updated() {
      if (!this.map) return;
      this.map.update(this.extractOptions());
    },

    destroyed() {
      if (this.map) {
        this.map.destroy();
        this.map = null;
      }
    },

    extractOptions() {
      const dataset = this.el.dataset;
      const marker = parseLatLng(dataset.markerLat, dataset.markerLng);
      const actual = parseLatLng(dataset.actualLat, dataset.actualLng);
      const center = parseLatLng(dataset.centerLat, dataset.centerLng);
      const zoom =
        dataset.zoom === undefined ? undefined : parseZoom(dataset.zoom, 2);
      const controls =
        dataset.controls === undefined
          ? undefined
          : parseBoolean(dataset.controls, true);

      return {
        mode: dataset.mode || "submission",
        playerId: dataset.playerId || null,
        marker,
        actual,
        guesses: parseGuesses(dataset.guesses),
        center,
        zoom,
        controls,
      };
    },
  },
};

const parseJson = (value) => {
  if (!value) return [];
  try {
    return JSON.parse(value);
  } catch (error) {
    console.warn("Failed to parse JSON payload", error);
    return [];
  }
};

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}
