const state = {
  index: null,
  presets: [],
  selectedAnimationId: null,
  selectedSpritesheetUrl: null,
  fps: 16,
  currentImage: null,
  currentFrame: 0,
  lastTickMs: 0,
  animationFrameId: null,
  queueImage: null,
  queueFrame: 0,
  queueTickTimer: null,
  queueAnimationIndex: 0,
  queueImageUrl: null,
  currentJobId: null,
  currentJobStatus: null,
  jobPollTimer: null,
};

const nodes = {
  animationList: document.getElementById("animationList"),
  animationTitle: document.getElementById("animationTitle"),
  outputRoot: document.getElementById("outputRoot"),
  summary: document.getElementById("summary"),
  posesCount: document.getElementById("posesCount"),
  renderList: document.getElementById("renderList"),
  spriteCanvas: document.getElementById("spriteCanvas"),
  queueCanvas: document.getElementById("queueCanvas"),
  queueLabel: document.getElementById("queueLabel"),
  refreshButton: document.getElementById("refreshButton"),
  fpsRange: document.getElementById("fpsRange"),
  fpsValue: document.getElementById("fpsValue"),
  generateForm: document.getElementById("generateForm"),
  generateButton: document.getElementById("generateButton"),
  generateAllButton: document.getElementById("generateAllButton"),
  presetSelect: document.getElementById("presetSelect"),
  sourceFile: document.getElementById("sourceFile"),
  animationName: document.getElementById("animationName"),
  extraPrompt: document.getElementById("extraPrompt"),
  greyscaleCheckbox: document.getElementById("greyscaleCheckbox"),
  cellSizeSelect: document.getElementById("cellSizeSelect"),
  jobMeta: document.getElementById("jobMeta"),
  jobLog: document.getElementById("jobLog"),
};

const spriteContext = nodes.spriteCanvas.getContext("2d");
const queueContext = nodes.queueCanvas.getContext("2d");

function getRequestedAnimationId() {
  const params = new URLSearchParams(window.location.search);
  return params.get("animation");
}

function syncUrl() {
  const url = new URL(window.location.href);
  if (state.selectedAnimationId) {
    url.searchParams.set("animation", state.selectedAnimationId);
  } else {
    url.searchParams.delete("animation");
  }
  window.history.replaceState({}, "", url);
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, options);
  if (!response.ok) {
    throw new Error(`${url} failed: ${response.status}`);
  }
  return response.json();
}

async function loadPresets() {
  const payload = await fetchJson("/api/presets", { cache: "no-store" });
  state.presets = payload.presets ?? [];
  nodes.presetSelect.replaceChildren(
    ...state.presets.map((preset) => {
      const option = document.createElement("option");
      option.value = preset.slug;
      option.textContent = `${preset.label} (${preset.frames}f)`;
      return option;
    }),
  );
}

async function loadIndex() {
  state.index = await fetchJson("/api/index", { cache: "no-store" });

  if (!state.selectedAnimationId && state.index.animations.length > 0) {
    const requestedAnimationId = getRequestedAnimationId();
    const requestedAnimation = state.index.animations.find((item) => item.id === requestedAnimationId);
    state.selectedAnimationId = requestedAnimation?.id ?? state.index.animations[0].id;
  }

  if (state.selectedAnimationId) {
    const exists = state.index.animations.some((item) => item.id === state.selectedAnimationId);
    if (!exists) {
      state.selectedAnimationId = state.index.animations[0]?.id ?? null;
    }
  }

  const selectedAnimation = getSelectedAnimation();
  if (selectedAnimation) {
    const spriteExists = selectedAnimation.spritesheets.some((item) => item.url === state.selectedSpritesheetUrl);
    if (!spriteExists) {
      state.selectedSpritesheetUrl = selectedAnimation.spritesheets[0]?.url ?? null;
    }
  }

  render();
}

function getSelectedAnimation() {
  return state.index?.animations.find((item) => item.id === state.selectedAnimationId) ?? null;
}

function clearCanvas() {
  spriteContext.clearRect(0, 0, nodes.spriteCanvas.width, nodes.spriteCanvas.height);
}

function clearQueueCanvas() {
  queueContext.clearRect(0, 0, nodes.queueCanvas.width, nodes.queueCanvas.height);
}

function stopSpritePlayback() {
  if (state.animationFrameId !== null) {
    window.cancelAnimationFrame(state.animationFrameId);
    state.animationFrameId = null;
  }
}

function stopQueuePlayback() {
  if (state.queueTickTimer !== null) {
    window.clearTimeout(state.queueTickTimer);
    state.queueTickTimer = null;
  }
}

async function loadImageForUrl(url) {
  const image = new Image();
  image.dataset.url = url;
  image.decoding = "async";
  image.src = `${url}?t=${Date.now()}`;
  await image.decode();
  return image;
}

async function loadSpritesheet(url) {
  if (state.currentImage?.dataset?.url === url) {
    return;
  }

  stopSpritePlayback();
  const image = await loadImageForUrl(url);
  state.currentImage = image;
  state.currentFrame = 0;
  state.lastTickMs = 0;
  startSpritePlayback();
}

function startSpritePlayback() {
  stopSpritePlayback();

  const tick = (timestamp) => {
    if (!state.currentImage) {
      return;
    }

    const frameSize = state.currentImage.naturalHeight;
    const frameCount = Math.max(1, Math.floor(state.currentImage.naturalWidth / frameSize));
    const frameDurationMs = 1000 / Math.max(1, state.fps);

    if (nodes.spriteCanvas.width !== frameSize || nodes.spriteCanvas.height !== frameSize) {
      nodes.spriteCanvas.width = frameSize;
      nodes.spriteCanvas.height = frameSize;
    }

    if (state.lastTickMs === 0) {
      state.lastTickMs = timestamp;
    } else if (timestamp - state.lastTickMs >= frameDurationMs) {
      const elapsedFrames = Math.max(1, Math.floor((timestamp - state.lastTickMs) / frameDurationMs));
      state.currentFrame = (state.currentFrame + elapsedFrames) % frameCount;
      state.lastTickMs = timestamp;
    }

    const sx = state.currentFrame * frameSize;
    spriteContext.clearRect(0, 0, frameSize, frameSize);
    spriteContext.drawImage(state.currentImage, sx, 0, frameSize, frameSize, 0, 0, frameSize, frameSize);
    state.animationFrameId = window.requestAnimationFrame(tick);
  };

  state.animationFrameId = window.requestAnimationFrame(tick);
}

function getPlaylistAnimations() {
  return (state.index?.animations ?? []).filter((animation) => animation.spritesheets?.length);
}

async function loadQueueSpritesheet(url, forceRestart = false) {
  if (state.queueImageUrl === url && state.queueImage) {
    state.queueFrame = 0;
    return;
  }

  const image = await loadImageForUrl(url);
  state.queueImage = image;
  state.queueImageUrl = url;
  state.queueFrame = 0;
}

function drawQueueFrame() {
  if (!state.queueImage) {
    clearQueueCanvas();
    return;
  }

  const frameSize = state.queueImage.naturalHeight;
  const frameCount = Math.max(1, Math.floor(state.queueImage.naturalWidth / frameSize));
  if (nodes.queueCanvas.width !== frameSize || nodes.queueCanvas.height !== frameSize) {
    nodes.queueCanvas.width = frameSize;
    nodes.queueCanvas.height = frameSize;
  }

  const sx = (state.queueFrame % frameCount) * frameSize;
  queueContext.clearRect(0, 0, frameSize, frameSize);
  queueContext.drawImage(state.queueImage, sx, 0, frameSize, frameSize, 0, 0, frameSize, frameSize);
}

async function queueTick() {
  const playlist = getPlaylistAnimations();
  if (!playlist.length) {
    nodes.queueLabel.textContent = "No generated animations yet";
    state.queueImage = null;
    state.queueImageUrl = null;
    stopQueuePlayback();
    clearQueueCanvas();
    return;
  }
  if (!state.queueImage) {
    const current = playlist[state.queueAnimationIndex] ?? playlist[0];
    nodes.queueLabel.textContent = current.title;
    await loadQueueSpritesheet(current.spritesheets[0].url);
    drawQueueFrame();
    scheduleQueueTick();
    return;
  }

  const frameSize = state.queueImage.naturalHeight;
  const frameCount = Math.max(1, Math.floor(state.queueImage.naturalWidth / frameSize));
  state.queueFrame += 1;

  if (state.queueFrame >= frameCount) {
    state.queueAnimationIndex = (state.queueAnimationIndex + 1) % playlist.length;
    const nextAnimation = playlist[state.queueAnimationIndex];
    nodes.queueLabel.textContent = nextAnimation.title;
    await loadQueueSpritesheet(nextAnimation.spritesheets[0].url, true);
  } else {
    drawQueueFrame();
  }

  scheduleQueueTick();
}

function scheduleQueueTick() {
  stopQueuePlayback();
  state.queueTickTimer = window.setTimeout(() => {
    queueTick().catch(showError);
  }, 1000 / Math.max(1, state.fps));
}

function startQueuePlayback() {
  stopQueuePlayback();
  queueTick().catch(showError);
}

function ensureQueuePlayback() {
  const playlist = getPlaylistAnimations();
  if (!playlist.length) {
    nodes.queueLabel.textContent = "No generated animations yet";
    state.queueImage = null;
    state.queueImageUrl = null;
    stopQueuePlayback();
    clearQueueCanvas();
    return;
  }

  if (state.queueAnimationIndex >= playlist.length) {
    state.queueAnimationIndex = 0;
  }

  const current = playlist[state.queueAnimationIndex];
  if (state.queueImageUrl === current.spritesheets[0].url && state.queueTickTimer !== null) {
    return;
  }
  nodes.queueLabel.textContent = current.title;
  state.queueImage = null;
  state.queueImageUrl = null;
  state.queueFrame = 0;
  startQueuePlayback();
}

function renderJob() {
  if (!state.currentJobStatus) {
    nodes.jobMeta.textContent = "No active job";
    nodes.jobLog.textContent = "";
    nodes.generateButton.disabled = false;
    nodes.generateAllButton.disabled = false;
    return;
  }

  const { status, params, result, error, log } = state.currentJobStatus;
  const extraPromptSuffix = params.extra_prompt ? ` | +prompt=${params.extra_prompt}` : "";
  const scope = params.mode === "all" ? `all=${params.preset_count}` : `preset=${params.preset}`;
  nodes.jobMeta.textContent = `${status.toUpperCase()} | ${scope} | size=${params.cell_size} | ${params.greyscale ? "BW" : "Color"}${extraPromptSuffix}`;
  nodes.jobLog.textContent = `${log ?? ""}${error ? `\nERROR: ${error}` : ""}`;
  nodes.jobLog.scrollTop = nodes.jobLog.scrollHeight;
  nodes.generateButton.disabled = status === "queued" || status === "running";
  nodes.generateAllButton.disabled = status === "queued" || status === "running";

  if (status === "succeeded" && result?.animation_name) {
    state.selectedAnimationId = result.animation_name;
  }
}

function render() {
  const animations = state.index?.animations ?? [];
  nodes.outputRoot.textContent = state.index ? `Output: ${state.index.output_root}` : "";
  nodes.summary.textContent = `${animations.length} animation(s), W3 spritesheet preview`;
  nodes.fpsRange.value = String(state.fps);
  nodes.fpsValue.textContent = String(state.fps);

  nodes.animationList.replaceChildren(
    ...animations.map((animation) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `animation-card${animation.id === state.selectedAnimationId ? " active" : ""}`;
      button.innerHTML = `
        <span class="card-title">${animation.title}</span>
        <span class="card-meta">${animation.spritesheets.length} sheet(s)</span>
      `;
      button.addEventListener("click", () => {
        state.selectedAnimationId = animation.id;
        state.selectedSpritesheetUrl = animation.spritesheets[0]?.url ?? null;
        syncUrl();
        render();
      });
      return button;
    }),
  );

  const selectedAnimation = getSelectedAnimation();
  if (!selectedAnimation) {
    nodes.animationTitle.textContent = "No animation";
    nodes.posesCount.textContent = "";
    nodes.renderList.replaceChildren();
    stopSpritePlayback();
    clearCanvas();
    ensureQueuePlayback();
    renderJob();
    return;
  }

  syncUrl();
  nodes.animationTitle.textContent = selectedAnimation.title;
  nodes.posesCount.textContent = `${selectedAnimation.poses_count} pose(s)`;

  const selectedSpritesheet =
    selectedAnimation.spritesheets.find((item) => item.url === state.selectedSpritesheetUrl) ??
    selectedAnimation.spritesheets[0];
  if (selectedSpritesheet) {
    state.selectedSpritesheetUrl = selectedSpritesheet.url;
    loadSpritesheet(selectedSpritesheet.url).catch(showError);
  } else {
    stopSpritePlayback();
    clearCanvas();
  }

  nodes.renderList.replaceChildren(
    ...selectedAnimation.spritesheets.map((renderItem) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `render-card${renderItem.url === state.selectedSpritesheetUrl ? " active" : ""}`;
      button.innerHTML = `
        <span class="card-title">${renderItem.name}</span>
        <span class="card-meta">${renderItem.size_mb} MB</span>
      `;
      button.addEventListener("click", () => {
        state.selectedSpritesheetUrl = renderItem.url;
        render();
      });
      return button;
    }),
  );

  ensureQueuePlayback();
  renderJob();
}

async function pollJob(jobId) {
  try {
    const payload = await fetchJson(`/api/jobs/${jobId}`, { cache: "no-store" });
    state.currentJobStatus = payload;
    renderJob();
    if (payload.status === "succeeded") {
      await loadIndex();
      stopJobPolling();
    } else if (payload.status === "failed") {
      stopJobPolling();
    }
  } catch (error) {
    showError(error);
    stopJobPolling();
  }
}

function startJobPolling(jobId) {
  stopJobPolling();
  state.currentJobId = jobId;
  state.jobPollTimer = window.setInterval(() => {
    pollJob(jobId).catch(showError);
  }, 2000);
  pollJob(jobId).catch(showError);
}

function stopJobPolling() {
  if (state.jobPollTimer !== null) {
    window.clearInterval(state.jobPollTimer);
    state.jobPollTimer = null;
  }
}

async function handleGenerateSubmit(event) {
  event.preventDefault();
  if (!nodes.sourceFile.files.length) {
    nodes.jobMeta.textContent = "Choose a source image first";
    return;
  }

  const formData = new FormData();
  formData.set("source_file", nodes.sourceFile.files[0]);
  formData.set("preset", nodes.presetSelect.value);
  formData.set("cell_size", nodes.cellSizeSelect.value);
  formData.set("animation_name", nodes.animationName.value.trim());
  formData.set("extra_prompt", nodes.extraPrompt.value.trim());
  formData.set("greyscale", nodes.greyscaleCheckbox.checked ? "true" : "false");

  nodes.generateButton.disabled = true;
  nodes.jobMeta.textContent = "Submitting job...";
  try {
    const payload = await fetchJson("/api/generate", {
      method: "POST",
      body: formData,
    });
    state.currentJobStatus = payload;
    startJobPolling(payload.id);
  } catch (error) {
    nodes.generateButton.disabled = false;
    nodes.generateAllButton.disabled = false;
    showError(error);
  }
}

async function handleGenerateAll() {
  if (!nodes.sourceFile.files.length) {
    nodes.jobMeta.textContent = "Choose a source image first";
    return;
  }

  const formData = new FormData();
  formData.set("source_file", nodes.sourceFile.files[0]);
  formData.set("cell_size", nodes.cellSizeSelect.value);
  formData.set("animation_name", nodes.animationName.value.trim());
  formData.set("extra_prompt", nodes.extraPrompt.value.trim());
  formData.set("greyscale", nodes.greyscaleCheckbox.checked ? "true" : "false");

  nodes.generateButton.disabled = true;
  nodes.generateAllButton.disabled = true;
  nodes.jobMeta.textContent = "Submitting batch job...";
  try {
    const payload = await fetchJson("/api/generate-all", {
      method: "POST",
      body: formData,
    });
    state.currentJobStatus = payload;
    startJobPolling(payload.id);
  } catch (error) {
    nodes.generateButton.disabled = false;
    nodes.generateAllButton.disabled = false;
    showError(error);
  }
}

function showError(error) {
  nodes.summary.textContent = error.message;
}

nodes.refreshButton.addEventListener("click", () => {
  loadIndex().catch(showError);
});

nodes.fpsRange.addEventListener("input", (event) => {
  state.fps = Number(event.target.value);
  nodes.fpsValue.textContent = String(state.fps);
  if (state.queueImage) {
    startQueuePlayback();
  }
});

nodes.generateForm.addEventListener("submit", (event) => {
  handleGenerateSubmit(event).catch(showError);
});

nodes.generateAllButton.addEventListener("click", () => {
  handleGenerateAll().catch(showError);
});

Promise.all([loadPresets(), loadIndex()]).catch(showError);
window.setInterval(() => loadIndex().catch(showError), 7000);
