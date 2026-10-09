const ELEMENT_NAME = "animated-character";
const DEFAULT_FPS = 16;
const DEFAULT_VISEME = "rest";

const RHUBARB_VISEMES = Object.freeze({
  A: "MBP",
  B: "I",
  C: "E",
  D: "A_AI",
  E: "O",
  F: "U",
  G: "FV",
  H: "L",
  X: "rest",
});

const BUILTIN_COMMANDS = Object.freeze({
  "подними руку": ["raise_right_hand", "wave_right", "raise_left_hand", "wave_left"],
  "подними правую руку": ["raise_right_hand", "wave_right"],
  "подними левую руку": ["raise_left_hand", "wave_left"],
  "помаши рукой": ["wave_right", "wave_left"],
  "помаши правой рукой": ["wave_right"],
  "помаши левой рукой": ["wave_left"],
  "махни рукой": ["wave_right", "wave_left"],
  "кивни": ["nod"],
  "покачай головой": ["shake_head"],
  "посмотри налево": ["look_left"],
  "посмотри направо": ["look_right"],
  "укажи налево": ["point_left"],
  "укажи направо": ["point_right"],
  "прыгни": ["jump_vertical", "bounce"],
  "хлопни": ["clap_once"],
  "пожми плечами": ["shrug"],
  "поприветствуй": ["welcome", "wave_right", "wave_left"],
  "стой спокойно": ["idle", "idle_breathing"],
  "улыбнись": ["idle_smile", "smile"],
});

function createDeferred() {
  let resolve;
  let reject;
  const promise = new Promise((onResolve, onReject) => {
    resolve = onResolve;
    reject = onReject;
  });
  return { promise, resolve, reject };
}

function abortError(message = "Playback was stopped") {
  return new DOMException(message, "AbortError");
}

function normalizeCommandText(value) {
  return String(value ?? "")
    .normalize("NFKC")
    .toLocaleLowerCase("ru-RU")
    .replaceAll("ё", "е")
    .replace(/[^\p{L}\p{N}_]+/gu, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function finiteNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function positiveInteger(value, fallback = 0) {
  const number = Math.trunc(Number(value));
  return Number.isFinite(number) && number > 0 ? number : fallback;
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

function resolveUrl(value, baseUrl) {
  const source = typeof value === "string"
    ? value
    : value?.src ?? value?.url ?? value?.spritesheet_src ?? value?.spritesheet_url;
  if (!source) return null;
  return new URL(String(source), baseUrl).href;
}

function normalizePlayback(value) {
  const playback = String(value || "once_return").toLowerCase();
  return playback === "loop" ? "loop" : "once_return";
}

function normalizeRoi(value) {
  if (!value || typeof value !== "object") return null;
  const roi = {
    x: Math.trunc(finiteNumber(value.x, -1)),
    y: Math.trunc(finiteNumber(value.y, -1)),
    width: positiveInteger(value.width ?? value.w),
    height: positiveInteger(value.height ?? value.h),
  };
  return roi.x >= 0 && roi.y >= 0 && roi.width > 0 && roi.height > 0 ? roi : null;
}

function normalizeAction(id, value, baseUrl) {
  const record = typeof value === "string" ? { src: value } : value;
  if (!record || typeof record !== "object") {
    throw new TypeError(`Action ${id} must be an object`);
  }
  const src = resolveUrl(record, baseUrl);
  if (!src) throw new TypeError(`Action ${id} has no spritesheet src`);
  const frameCount = positiveInteger(record.frame_count ?? record.frameCount);
  const entryFrame = Math.max(0, Math.trunc(finiteNumber(
    record.entry_frame ?? record.entryFrame ?? record.entry_gate_frame,
    0,
  )));
  const requestedExit = record.exit_frame ?? record.exitFrame ?? record.exit_gate_frame;
  const exitFrame = requestedExit == null
    ? null
    : Math.max(entryFrame, Math.trunc(finiteNumber(requestedExit, entryFrame)));
  const aliases = Array.isArray(record.aliases)
    ? record.aliases.map(normalizeCommandText).filter(Boolean)
    : [];
  const roiTrackSource = record.mouth_roi_track ?? record.mouthRoiTrack;
  const mouthRoiTrack = Array.isArray(roiTrackSource)
    ? roiTrackSource.map(normalizeRoi)
    : null;
  const overlayRecord = record.overlay;
  const overlayRoi = normalizeRoi(overlayRecord);
  const overlaySrc = overlayRecord && typeof overlayRecord === "object"
    ? resolveUrl(overlayRecord, baseUrl)
    : null;
  return {
    id,
    src,
    frameCount,
    fps: Math.max(1, finiteNumber(record.fps, DEFAULT_FPS)),
    playback: normalizePlayback(record.playback),
    entryFrame,
    exitFrame,
    aliases,
    mouthRoi: normalizeRoi(record.mouth_roi ?? record.mouthRoi),
    mouthRoiTrack,
    overlay: overlaySrc && overlayRoi ? { src: overlaySrc, ...overlayRoi } : null,
  };
}

function normalizeAtlas(value, mouth, baseUrl) {
  if (!value || typeof value !== "object") return null;
  const src = resolveUrl(value, baseUrl)
    ?? resolveUrl(mouth?.atlas_image, baseUrl)
    ?? resolveUrl(mouth?.atlasImage, baseUrl);
  if (!src) return null;
  const rawCells = Array.isArray(value.cells) ? value.cells : [];
  const cells = rawCells.map((cell) => ({
    viseme: String(cell.viseme ?? cell.id ?? ""),
    x: Math.max(0, Math.trunc(finiteNumber(cell.x, 0))),
    y: Math.max(0, Math.trunc(finiteNumber(cell.y, 0))),
    width: positiveInteger(cell.width ?? cell.w),
    height: positiveInteger(cell.height ?? cell.h),
  })).filter((cell) => cell.viseme && cell.width > 0 && cell.height > 0);
  return { src, cells };
}

function normalizeTimeline(value) {
  if (!value) return [];
  const source = Array.isArray(value)
    ? value
    : value.segments ?? value.cues ?? value.mouthCues ?? value.visemes ?? [];
  if (!Array.isArray(source)) return [];
  return source.map((segment, index) => {
    const start = finiteNumber(
      segment.start_seconds ?? segment.start ?? segment.time ?? segment.offset,
      0,
    );
    const next = source[index + 1];
    const inferredEnd = next
      ? finiteNumber(next.start_seconds ?? next.start ?? next.time ?? next.offset, start)
      : start + 0.1;
    let rawEnd = segment.end_seconds ?? segment.end ?? segment.stop;
    const duration = segment.duration_seconds ?? segment.duration;
    if (rawEnd == null && duration != null) {
      rawEnd = start + finiteNumber(duration, 0);
    }
    const end = finiteNumber(rawEnd, inferredEnd);
    const rawViseme = String(segment.viseme ?? segment.value ?? segment.shape ?? DEFAULT_VISEME);
    const viseme = RHUBARB_VISEMES[rawViseme.toUpperCase()] ?? rawViseme;
    return { start: Math.max(0, start), end: Math.max(start, end), viseme };
  }).filter((segment) => segment.end > segment.start)
    .sort((left, right) => left.start - right.start);
}

function normalizeManifest(rawManifest, baseUrl) {
  if (!rawManifest || typeof rawManifest !== "object" || Array.isArray(rawManifest)) {
    throw new TypeError("Character manifest must be an object");
  }
  const canvas = rawManifest.canvas ?? rawManifest.anchor?.canvas ?? {};
  const width = positiveInteger(canvas.width);
  const height = positiveInteger(canvas.height);
  if (!width || !height) throw new TypeError("Manifest canvas width and height are required");

  const actionSource = rawManifest.actions ?? rawManifest.motions;
  if (!actionSource || typeof actionSource !== "object" || Array.isArray(actionSource)) {
    throw new TypeError("Manifest actions must be an object");
  }
  const actions = {};
  for (const [id, value] of Object.entries(actionSource)) {
    actions[id] = normalizeAction(id, value, baseUrl);
  }
  if (!Object.keys(actions).length) throw new TypeError("Manifest contains no actions");

  const neutralRecord = rawManifest.neutral ?? {};
  let neutralSrc = resolveUrl(neutralRecord, baseUrl);
  let neutralFrame = Math.max(0, Math.trunc(finiteNumber(neutralRecord.frame, 0)));
  const defaultAction = String(
    rawManifest.default_action
      ?? rawManifest.defaultAction
      ?? rawManifest.idle
      ?? (actions.idle ? "idle" : actions.idle_breathing ? "idle_breathing" : ""),
  );
  if (!neutralSrc && actions[defaultAction]) {
    neutralSrc = actions[defaultAction].src;
    neutralFrame = actions[defaultAction].entryFrame;
  }
  if (!neutralSrc) {
    const firstAction = Object.values(actions)[0];
    neutralSrc = firstAction.src;
    neutralFrame = firstAction.entryFrame;
  }

  const rawCommands = rawManifest.commands && typeof rawManifest.commands === "object"
    ? rawManifest.commands
    : {};
  const commands = {};
  for (const [alias, target] of Object.entries(rawCommands)) {
    const normalizedAlias = normalizeCommandText(alias);
    const motionId = typeof target === "string" ? target : target?.action ?? target?.motion;
    if (normalizedAlias && motionId) commands[normalizedAlias] = String(motionId);
  }

  const mouth = rawManifest.mouth ?? rawManifest.channels?.mouth ?? null;
  const atlas = mouth ? normalizeAtlas(mouth.atlas, mouth, baseUrl) : null;
  const bundledAudio = mouth
    ? resolveUrl(mouth.audio, baseUrl) ?? resolveUrl(mouth.audio_src ?? mouth.audioSrc, baseUrl)
    : null;

  return {
    schema: String(rawManifest.schema ?? "character.web-component.v1"),
    id: String(rawManifest.id ?? "character"),
    canvas: { width, height },
    defaultAction: actions[defaultAction] ? defaultAction : null,
    defaultSide: String(rawManifest.default_side ?? rawManifest.defaultSide ?? "right"),
    neutral: { src: neutralSrc, frame: neutralFrame },
    actions,
    commands,
    mouth: mouth ? {
      atlas,
      roi: normalizeRoi(mouth.roi ?? mouth.mouth_roi ?? rawManifest.anchor?.mouth_roi),
      timeline: normalizeTimeline(mouth.timeline),
      audio: bundledAudio,
    } : null,
  };
}

function eventDetail(element, type, detail) {
  element.dispatchEvent(new CustomEvent(type, {
    detail,
    bubbles: true,
    composed: true,
  }));
}

export class AnimatedCharacter extends HTMLElement {
  static get observedAttributes() {
    return ["src", "idle", "width", "height", "lipsync-endpoint"];
  }

  constructor() {
    super();
    const shadow = this.attachShadow({ mode: "open" });
    shadow.innerHTML = `
      <style>
        :host {
          display: inline-block;
          width: 100%;
          max-width: 100%;
          line-height: 0;
          contain: content;
        }
        canvas {
          display: block;
          width: 100%;
          height: auto;
          background: transparent;
        }
      </style>
      <canvas part="canvas" aria-label="Animated character"></canvas>
      <audio part="audio" preload="auto"></audio>
    `;
    this._canvas = shadow.querySelector("canvas");
    this._context = this._canvas.getContext("2d");
    this._audio = shadow.querySelector("audio");
    this._audio.hidden = true;
    this._audio.addEventListener("ended", () => this._finishSpeech("ended"));
    this._audio.addEventListener("error", () => {
      if (!this._speech) return;
      const error = new Error("Audio playback failed");
      this._finishSpeech("error", error);
    });

    this._manifest = null;
    this._manifestBase = new URL(document.baseURI);
    this._images = new Map();
    this._aliases = new Map();
    this._current = null;
    this._queue = [];
    this._raf = null;
    this._lastTimestamp = null;
    this._loadVersion = 0;
    this._loadedSrc = null;
    this._activeViseme = DEFAULT_VISEME;
    this._speech = null;
    this._objectAudioUrl = null;
    this._ready = Promise.resolve(this);
  }

  connectedCallback() {
    this._applyDisplaySize();
    const src = this.getAttribute("src");
    if (src && src !== this._loadedSrc) this._autoload(src);
    else if (this._manifest && !this._current) this._startDefaultAction();
  }

  disconnectedCallback() {
    this._halt({ reason: "disconnected", emit: false });
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (oldValue === newValue) return;
    if (name === "src" && this.isConnected && newValue) this._autoload(newValue);
    if (name === "width" || name === "height") this._applyDisplaySize();
    if (name === "idle" && this._manifest && !this._current && !this._queue.length) {
      this._startDefaultAction();
    }
  }

  get ready() {
    return this._ready;
  }

  get manifest() {
    return this._manifest;
  }

  get availableCommands() {
    if (!this._manifest) return [];
    return [...new Set([...Object.keys(this._manifest.actions), ...this._aliases.keys()])];
  }

  get currentAction() {
    return this._current?.action.id ?? null;
  }

  get lipsyncEndpoint() {
    return this.getAttribute("lipsync-endpoint") || null;
  }

  set lipsyncEndpoint(value) {
    if (value) this.setAttribute("lipsync-endpoint", value);
    else this.removeAttribute("lipsync-endpoint");
  }

  async load(source) {
    const version = ++this._loadVersion;
    const ready = createDeferred();
    this._ready = ready.promise;
    // Attribute-driven loads may have no immediate `ready` consumer. Keep the
    // rejection observable to callers without producing a global unhandled
    // rejection in that case.
    this._ready.catch(() => {});
    this._halt({ reason: "reloaded", emit: false });
    this._images.clear();
    this._manifest = null;

    try {
      let rawManifest;
      let baseUrl;
      if (typeof source === "string" || source instanceof URL) {
        const manifestUrl = new URL(String(source), document.baseURI);
        const response = await fetch(manifestUrl, { cache: "no-store" });
        if (!response.ok) throw new Error(`Manifest request failed: ${response.status} ${response.statusText}`);
        rawManifest = await response.json();
        baseUrl = manifestUrl;
        this._loadedSrc = String(source);
      } else {
        rawManifest = source;
        const declaredBase = rawManifest?.base_url ?? rawManifest?.baseUrl ?? document.baseURI;
        baseUrl = new URL(String(declaredBase), document.baseURI);
        this._loadedSrc = null;
      }
      const manifest = normalizeManifest(rawManifest, baseUrl);
      const urls = new Set([
        manifest.neutral.src,
        ...Object.values(manifest.actions).map((action) => action.src),
        ...Object.values(manifest.actions).map((action) => action.overlay?.src),
        manifest.mouth?.atlas?.src,
      ].filter(Boolean));
      await Promise.all([...urls].map((url) => this._loadImage(url)));
      if (version !== this._loadVersion) throw abortError("A newer manifest replaced this load");

      for (const action of Object.values(manifest.actions)) {
        const image = this._images.get(action.src);
        const inferredFrames = Math.max(1, Math.floor(image.naturalWidth / manifest.canvas.width));
        action.frameCount = action.frameCount || inferredFrames;
        action.exitFrame = action.exitFrame == null
          ? action.frameCount - 1
          : clamp(action.exitFrame, action.entryFrame, action.frameCount - 1);
        action.entryFrame = clamp(action.entryFrame, 0, action.exitFrame);
      }
      manifest.neutral.frame = Math.max(0, manifest.neutral.frame);
      this._manifestBase = baseUrl;
      this._manifest = manifest;
      this._canvas.width = manifest.canvas.width;
      this._canvas.height = manifest.canvas.height;
      this._canvas.style.aspectRatio = `${manifest.canvas.width} / ${manifest.canvas.height}`;
      this._buildAliases();
      this._draw();
      this._startDefaultAction();
      ready.resolve(this);
      eventDetail(this, "character-ready", {
        id: manifest.id,
        actions: Object.keys(manifest.actions),
      });
      return this;
    } catch (error) {
      ready.reject(error);
      this._reportError(error, "load");
      throw error;
    }
  }

  async command(command, options = {}) {
    try {
      await this.ready;
      const actionId = this._resolveCommand(command);
      if (!actionId) throw new RangeError(`Unknown character command: ${JSON.stringify(command)}`);
      eventDetail(this, "commandstart", { command, actionId });
      const result = await this.play(actionId, options);
      eventDetail(this, "commandend", { command, actionId, result });
      return result;
    } catch (error) {
      eventDetail(this, "commanderror", { command, error, message: error.message });
      throw error;
    }
  }

  async play(actionId, options = {}) {
    await this.ready;
    if (!this._manifest) throw new Error("Character is not loaded");
    const action = this._manifest.actions[String(actionId)];
    if (!action) throw new RangeError(`Unknown character action: ${actionId}`);
    const deferred = createDeferred();
    const request = { action, deferred, idle: false };

    if (!this._current) {
      this._startRequest(request);
    } else if (this._current.idle || this._current.action.playback === "loop" || options.interrupt === "immediate") {
      this._cancelCurrent("interrupted", options.interrupt === "immediate");
      this._startRequest(request);
    } else {
      if (options.queue !== "append") {
        for (const queued of this._queue.splice(0)) queued.deferred.reject(abortError("Replaced by a newer action"));
      }
      this._queue.push(request);
      eventDetail(this, "motionqueued", {
        actionId: action.id,
        position: this._queue.length,
      });
    }
    return deferred.promise;
  }

  async speak(input = {}, options = {}) {
    await this.ready;
    if (!this._manifest) throw new Error("Character is not loaded");
    const descriptor = input instanceof Blob || typeof input === "string" || input instanceof URL
      ? { audio: input, ...options }
      : { ...input, ...options };
    const bundled = !descriptor.audio;
    const audioInput = descriptor.audio ?? this._manifest.mouth?.audio;
    if (!audioInput) throw new TypeError("speak() requires audio or a bundled mouth.audio source");

    this._stopSpeech(abortError("Replaced by a newer speech"));
    let timelineInput = descriptor.timeline ?? descriptor.timings;
    if (!timelineInput && bundled) timelineInput = this._manifest.mouth?.timeline;
    if (!timelineInput && this.lipsyncEndpoint && audioInput instanceof Blob) {
      timelineInput = await this._requestLipSync(audioInput, descriptor.transcript || "");
    }
    const timeline = normalizeTimeline(timelineInput);
    const deferred = createDeferred();

    let audioUrl;
    if (audioInput instanceof Blob) {
      this._objectAudioUrl = URL.createObjectURL(audioInput);
      audioUrl = this._objectAudioUrl;
    } else {
      audioUrl = new URL(String(audioInput), bundled ? this._manifestBase : document.baseURI).href;
    }
    this._speech = { deferred, timeline, audioUrl };
    this._activeViseme = DEFAULT_VISEME;
    this._audio.src = audioUrl;
    this._audio.currentTime = 0;
    this._audio.load();
    try {
      await this._audio.play();
    } catch (error) {
      this._finishSpeech("error", error);
      throw error;
    }
    eventDetail(this, "speechstart", {
      lipSync: timeline.length > 0,
      segmentCount: timeline.length,
    });
    this._ensureAnimation();
    return deferred.promise;
  }

  stop() {
    this._halt({ reason: "stopped", emit: true });
  }

  pause() {
    if (this._raf !== null) cancelAnimationFrame(this._raf);
    this._raf = null;
    this._lastTimestamp = null;
    if (!this._audio.paused) this._audio.pause();
    eventDetail(this, "characterpause", { actionId: this.currentAction });
  }

  async resume() {
    if (this._speech && this._audio.paused && !this._audio.ended) await this._audio.play();
    this._ensureAnimation();
    eventDetail(this, "characterresume", { actionId: this.currentAction });
  }

  _autoload(src) {
    this.load(src).catch(() => {
      // The load error is already exposed through charactererror and ready.
    });
  }

  _applyDisplaySize() {
    const width = this.getAttribute("width");
    const height = this.getAttribute("height");
    this.style.width = width ? (/^\d+(?:\.\d+)?$/.test(width) ? `${width}px` : width) : "";
    this.style.height = height ? (/^\d+(?:\.\d+)?$/.test(height) ? `${height}px` : height) : "";
  }

  _loadImage(url) {
    const existing = this._images.get(url);
    if (existing instanceof HTMLImageElement) return Promise.resolve(existing);
    if (existing) return existing;
    const promise = new Promise((resolve, reject) => {
      const image = new Image();
      const crossOrigin = this.getAttribute("crossorigin");
      if (crossOrigin !== null) image.crossOrigin = crossOrigin || "anonymous";
      image.decoding = "async";
      image.addEventListener("load", () => {
        this._images.set(url, image);
        resolve(image);
      }, { once: true });
      image.addEventListener("error", () => {
        this._images.delete(url);
        reject(new Error(`Failed to load character image: ${url}`));
      }, { once: true });
      image.src = url;
    });
    this._images.set(url, promise);
    return promise;
  }

  _buildAliases() {
    this._aliases.clear();
    for (const [alias, actionId] of Object.entries(this._manifest.commands)) {
      if (this._manifest.actions[actionId]) this._aliases.set(alias, actionId);
    }
    for (const action of Object.values(this._manifest.actions)) {
      this._aliases.set(normalizeCommandText(action.id), action.id);
      for (const alias of action.aliases) this._aliases.set(alias, action.id);
    }
    for (const [alias, candidates] of Object.entries(BUILTIN_COMMANDS)) {
      const actionId = this._firstAvailable(candidates);
      if (actionId && !this._aliases.has(alias)) this._aliases.set(alias, actionId);
    }
  }

  _firstAvailable(candidates) {
    const side = this._manifest.defaultSide === "left" ? "left" : "right";
    const sorted = [...candidates].sort((left, right) => {
      const leftPreferred = left.includes(`_${side}`) ? 0 : 1;
      const rightPreferred = right.includes(`_${side}`) ? 0 : 1;
      return leftPreferred - rightPreferred;
    });
    return sorted.find((id) => this._manifest.actions[id]) ?? null;
  }

  _resolveCommand(command) {
    if (command && typeof command === "object") {
      const action = String(command.action ?? command.motion ?? "");
      const side = String(command.side ?? this._manifest.defaultSide ?? "right");
      if (this._manifest.actions[action]) return action;
      const sided = `${action}_${side}`;
      if (this._manifest.actions[sided]) return sided;
      if (action === "raise_hand") {
        return this._firstAvailable([`raise_${side}_hand`, `wave_${side}`]);
      }
      return null;
    }
    const raw = String(command ?? "").trim();
    if (this._manifest.actions[raw]) return raw;
    return this._aliases.get(normalizeCommandText(raw)) ?? null;
  }

  _startRequest(request) {
    const { action, deferred, idle } = request;
    this._current = {
      action,
      deferred,
      idle,
      frame: action.entryFrame,
      accumulator: 0,
    };
    this._lastTimestamp = null;
    this._draw();
    eventDetail(this, "motionstart", { actionId: action.id, idle });
    if (action.playback === "loop" && deferred) {
      deferred.resolve({ actionId: action.id, status: "started", playback: "loop" });
      this._current.deferred = null;
    }
    this._ensureAnimation();
  }

  _startDefaultAction() {
    if (!this._manifest || this._current || this._queue.length) return;
    const requested = this.getAttribute("idle") || this._manifest.defaultAction;
    const action = requested ? this._manifest.actions[requested] : null;
    if (!action) {
      this._draw();
      return;
    }
    this._startRequest({ action, deferred: null, idle: true });
  }

  _completeCurrent() {
    const finished = this._current;
    if (!finished) return;
    this._current = null;
    this._draw();
    eventDetail(this, "motionend", {
      actionId: finished.action.id,
      idle: finished.idle,
      reason: "completed",
    });

    const next = this._queue.shift();
    if (next) this._startRequest(next);
    else this._startDefaultAction();
    finished.deferred?.resolve({
      actionId: finished.action.id,
      status: "completed",
      returnedTo: this.currentAction ?? "neutral",
    });
  }

  _cancelCurrent(reason, reject = false) {
    const current = this._current;
    if (!current) return;
    this._current = null;
    eventDetail(this, "motionend", {
      actionId: current.action.id,
      idle: current.idle,
      reason,
    });
    if (reject) current.deferred?.reject(abortError(`Action ${current.action.id} was interrupted`));
    else current.deferred?.resolve({ actionId: current.action.id, status: reason });
  }

  _advanceCurrent() {
    const current = this._current;
    if (!current) return false;
    if (current.frame >= current.action.exitFrame) {
      if (current.action.playback === "loop") {
        current.frame = current.action.entryFrame;
        return true;
      }
      this._completeCurrent();
      return false;
    }
    current.frame = Math.min(current.action.exitFrame, current.frame + 1);
    return true;
  }

  _ensureAnimation() {
    if (this._raf === null && (this._current || this._speech)) {
      this._lastTimestamp = null;
      this._raf = requestAnimationFrame((timestamp) => this._tick(timestamp));
    }
  }

  _tick(timestamp) {
    this._raf = null;
    const delta = this._lastTimestamp === null
      ? 0
      : clamp(timestamp - this._lastTimestamp, 0, 250);
    this._lastTimestamp = timestamp;
    const current = this._current;
    if (current) {
      current.accumulator += delta;
      const frameDuration = 1000 / current.action.fps;
      let advances = 0;
      while (this._current === current && current.accumulator >= frameDuration && advances < 8) {
        current.accumulator -= frameDuration;
        this._advanceCurrent();
        advances += 1;
      }
    }
    this._updateViseme();
    this._draw();
    if (this._current || this._speech) {
      this._raf = requestAnimationFrame((nextTimestamp) => this._tick(nextTimestamp));
    } else {
      this._lastTimestamp = null;
    }
  }

  _drawSheetFrame(image, frame) {
    if (!image || !this._manifest) return false;
    const { width, height } = this._manifest.canvas;
    const availableFrames = Math.max(1, Math.floor(image.naturalWidth / width));
    const index = clamp(Math.trunc(frame), 0, availableFrames - 1);
    this._context.drawImage(image, index * width, 0, width, height, 0, 0, width, height);
    return true;
  }

  _draw() {
    if (!this._manifest) return;
    const { width, height } = this._manifest.canvas;
    this._context.clearRect(0, 0, width, height);
    this._context.imageSmoothingEnabled = true;

    const current = this._current;
    const source = current
      ? { src: current.action.src, frame: current.frame }
      : this._manifest.neutral;
    const image = this._images.get(source.src);
    if (image instanceof HTMLImageElement) this._drawSheetFrame(image, source.frame);
    const overlay = current?.action.overlay;
    const overlayImage = overlay ? this._images.get(overlay.src) : null;
    if (overlayImage instanceof HTMLImageElement) {
      this._context.drawImage(
        overlayImage,
        0, 0, overlayImage.naturalWidth, overlayImage.naturalHeight,
        overlay.x, overlay.y, overlay.width, overlay.height,
      );
    }
    this._drawMouth();
  }

  _drawMouth() {
    const mouth = this._manifest?.mouth;
    const atlas = mouth?.atlas;
    if (!atlas?.cells?.length) return;
    const image = this._images.get(atlas.src);
    if (!(image instanceof HTMLImageElement)) return;
    const current = this._current;
    const trackedRoi = current?.action.mouthRoiTrack?.[current.frame] ?? null;
    const roi = trackedRoi ?? current?.action.mouthRoi ?? mouth.roi;
    if (!roi) return;
    const cell = atlas.cells.find((item) => item.viseme === this._activeViseme)
      ?? atlas.cells.find((item) => item.viseme === DEFAULT_VISEME);
    if (!cell) return;
    const { width, height } = this._manifest.canvas;
    if (roi.x + roi.width > width || roi.y + roi.height > height) return;
    this._context.drawImage(
      image,
      cell.x,
      cell.y,
      cell.width,
      cell.height,
      roi.x,
      roi.y,
      roi.width,
      roi.height,
    );
  }

  _updateViseme() {
    if (!this._speech?.timeline.length || this._audio.paused || this._audio.ended) {
      this._activeViseme = DEFAULT_VISEME;
      return;
    }
    const time = Math.max(0, this._audio.currentTime || 0);
    const segment = this._speech.timeline.find((item) => time >= item.start && time < item.end);
    this._activeViseme = segment?.viseme ?? DEFAULT_VISEME;
  }

  async _requestLipSync(audio, transcript) {
    const form = new FormData();
    form.append("audio", audio, audio.name || "voice.wav");
    if (transcript) form.append("transcript", transcript);
    const response = await fetch(new URL(this.lipsyncEndpoint, document.baseURI), {
      method: "POST",
      body: form,
    });
    if (!response.ok) throw new Error(`Lip-sync request failed: ${response.status} ${response.statusText}`);
    const payload = await response.json();
    return payload.timeline ?? payload.timings ?? payload;
  }

  _finishSpeech(reason, error = null) {
    const speech = this._speech;
    if (!speech) return;
    this._speech = null;
    this._activeViseme = DEFAULT_VISEME;
    this._audio.pause();
    if (this._objectAudioUrl) URL.revokeObjectURL(this._objectAudioUrl);
    this._objectAudioUrl = null;
    this._draw();
    if (error) speech.deferred.reject(error);
    else speech.deferred.resolve({ status: reason, lipSync: speech.timeline.length > 0 });
    eventDetail(this, error ? "speecherror" : "speechend", {
      reason,
      error,
      message: error?.message,
    });
  }

  _stopSpeech(error = null) {
    if (!this._speech) return;
    this._audio.pause();
    this._audio.currentTime = 0;
    this._finishSpeech(error ? "interrupted" : "stopped", error);
  }

  _halt({ reason, emit }) {
    if (this._raf !== null) cancelAnimationFrame(this._raf);
    this._raf = null;
    this._lastTimestamp = null;
    const current = this._current;
    this._current = null;
    current?.deferred?.reject(abortError(`Action stopped: ${reason}`));
    for (const queued of this._queue.splice(0)) queued.deferred.reject(abortError(`Action stopped: ${reason}`));
    this._stopSpeech(abortError(`Speech stopped: ${reason}`));
    this._activeViseme = DEFAULT_VISEME;
    this._draw();
    if (emit) eventDetail(this, "characterstop", { reason });
  }

  _reportError(error, phase) {
    eventDetail(this, "charactererror", { phase, error, message: error.message });
  }
}

if (!customElements.get(ELEMENT_NAME)) {
  customElements.define(ELEMENT_NAME, AnimatedCharacter);
}
