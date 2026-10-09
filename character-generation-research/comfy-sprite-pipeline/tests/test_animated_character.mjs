import assert from "node:assert/strict";
import test from "node:test";

class FakeEventTarget {
  constructor() {
    this.listeners = new Map();
  }

  addEventListener(type, listener) {
    const listeners = this.listeners.get(type) ?? [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  dispatchEvent(event) {
    event.target = this;
    for (const listener of this.listeners.get(event.type) ?? []) listener.call(this, event);
    return true;
  }
}

class FakeCustomEvent {
  constructor(type, options = {}) {
    this.type = type;
    this.detail = options.detail;
    this.bubbles = Boolean(options.bubbles);
    this.composed = Boolean(options.composed);
    this.target = null;
  }
}

const drawingCalls = [];
const context = {
  imageSmoothingEnabled: false,
  clearRect: (...args) => drawingCalls.push(["clearRect", ...args]),
  drawImage: (...args) => drawingCalls.push(["drawImage", ...args]),
  fillRect: (...args) => drawingCalls.push(["fillRect", ...args]),
};

class FakeCanvas extends FakeEventTarget {
  constructor() {
    super();
    this.width = 0;
    this.height = 0;
    this.style = {};
  }

  getContext() {
    return context;
  }
}

class FakeAudio extends FakeEventTarget {
  constructor() {
    super();
    this.hidden = false;
    this.paused = true;
    this.ended = false;
    this.currentTime = 0;
    this.src = "";
  }

  load() {}

  async play() {
    this.paused = false;
  }

  pause() {
    this.paused = true;
  }
}

class FakeHTMLElement extends FakeEventTarget {
  constructor() {
    super();
    this.attributes = new Map();
    this.style = {};
    this.isConnected = true;
    this.canvas = new FakeCanvas();
    this.audio = new FakeAudio();
  }

  attachShadow() {
    return {
      innerHTML: "",
      querySelector: (selector) => selector === "canvas" ? this.canvas : this.audio,
    };
  }

  getAttribute(name) {
    return this.attributes.get(name) ?? null;
  }

  setAttribute(name, value) {
    const oldValue = this.getAttribute(name);
    this.attributes.set(name, String(value));
    this.attributeChangedCallback?.(name, oldValue, String(value));
  }

  removeAttribute(name) {
    const oldValue = this.getAttribute(name);
    this.attributes.delete(name);
    this.attributeChangedCallback?.(name, oldValue, null);
  }
}

class FakeImage extends FakeEventTarget {
  constructor() {
    super();
    this.naturalWidth = 192;
    this.naturalHeight = 64;
    this.decoding = "auto";
  }

  set src(value) {
    this._src = value;
    queueMicrotask(() => this.dispatchEvent(new FakeCustomEvent("load")));
  }

  get src() {
    return this._src;
  }
}

globalThis.CustomEvent = FakeCustomEvent;
globalThis.HTMLElement = FakeHTMLElement;
globalThis.HTMLImageElement = FakeImage;
globalThis.Image = FakeImage;
globalThis.document = { baseURI: "http://example.test/" };
globalThis.customElements = {
  registry: new Map(),
  get(name) { return this.registry.get(name); },
  define(name, constructor) { this.registry.set(name, constructor); },
};
let animationId = 0;
globalThis.requestAnimationFrame = () => ++animationId;
globalThis.cancelAnimationFrame = () => {};

const { AnimatedCharacter } = await import("../viewer/static/animated-character.js");

function manifest() {
  return {
    schema: "character.web-component.v1",
    id: "hero",
    base_url: "http://example.test/character/manifest.json",
    canvas: { width: 64, height: 64 },
    default_action: "idle",
    neutral: { src: "neutral.png", frame: 0 },
    actions: {
      idle: {
        src: "idle.png",
        frame_count: 3,
        fps: 10,
        playback: "loop",
        aliases: ["стой"],
      },
      idle_smile: {
        src: "idle.png",
        frame_count: 3,
        fps: 10,
        playback: "loop",
        aliases: ["улыбнись"],
        overlay: { src: "smile-overlay.png", x: 16, y: 16, width: 32, height: 24 },
      },
      wave_right: {
        src: "wave.png",
        frame_count: 3,
        fps: 10,
        playback: "once_return",
      },
    },
  };
}

test("loads a self-contained manifest and keeps the canvas transparent", async () => {
  drawingCalls.length = 0;
  const character = new AnimatedCharacter();
  let readyDetail = null;
  character.addEventListener("character-ready", (event) => { readyDetail = event.detail; });

  await character.load(manifest());

  assert.equal(character.canvas.width, 64);
  assert.equal(character.canvas.height, 64);
  assert.equal(character.currentAction, "idle");
  assert.deepEqual(readyDetail.actions, ["idle", "idle_smile", "wave_right"]);
  assert.ok(drawingCalls.some(([name]) => name === "clearRect"));
  assert.ok(drawingCalls.some(([name]) => name === "drawImage"));
  assert.ok(!drawingCalls.some(([name]) => name === "fillRect"));
});

test("resolves a Russian one-shot command only after returning to idle", async () => {
  const character = new AnimatedCharacter();
  await character.load(manifest());
  const ended = [];
  character.addEventListener("motionend", (event) => ended.push(event.detail));

  const completion = character.command("подними руку");
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(character.currentAction, "wave_right");

  character._tick(0);
  character._tick(100);
  character._tick(200);
  character._tick(300);
  const result = await completion;

  assert.equal(result.status, "completed");
  assert.equal(result.returnedTo, "idle");
  assert.equal(character.currentAction, "idle");
  assert.ok(ended.some((event) => event.actionId === "wave_right" && event.reason === "completed"));
});

test("switches loop actions immediately and exposes manifest aliases", async () => {
  drawingCalls.length = 0;
  const character = new AnimatedCharacter();
  await character.load(manifest());

  const result = await character.command("улыбнись");

  assert.equal(result.status, "started");
  assert.equal(character.currentAction, "idle_smile");
  assert.ok(character.availableCommands.includes("улыбнись"));
  const draws = drawingCalls.filter(([name]) => name === "drawImage");
  assert.ok(draws.some((call) => call[6] === 16 && call[7] === 16 && call[8] === 32 && call[9] === 24));
});

test("plays supplied speech timings and emits speech lifecycle events", async () => {
  const character = new AnimatedCharacter();
  await character.load(manifest());
  const events = [];
  character.addEventListener("speechstart", (event) => events.push(["start", event.detail]));
  character.addEventListener("speechend", (event) => events.push(["end", event.detail]));

  const speaking = character.speak({
    audio: "voice.ogg",
    timings: [{ start: 0, end: 0.25, viseme: "A" }],
  });
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  character.audio.currentTime = 0.1;
  character._tick(0);
  character.audio.ended = true;
  character.audio.dispatchEvent(new FakeCustomEvent("ended"));
  const result = await speaking;

  assert.equal(result.status, "ended");
  assert.equal(result.lipSync, true);
  assert.equal(events[0][0], "start");
  assert.equal(events[0][1].segmentCount, 1);
  assert.equal(events[1][0], "end");
});

test("stop returns to neutral and aborts an unfinished one-shot", async () => {
  const character = new AnimatedCharacter();
  await character.load(manifest());
  const completion = character.command("подними руку");
  await Promise.resolve();
  await Promise.resolve();

  character.stop();

  await assert.rejects(completion, (error) => error.name === "AbortError");
  assert.equal(character.currentAction, null);
});
