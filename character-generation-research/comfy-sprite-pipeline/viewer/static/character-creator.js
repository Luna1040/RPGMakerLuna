const app = document.querySelector(".creator");
const charactersScreen = document.querySelector('[data-screen="characters"]');
const createScreen = document.querySelector('[data-screen="create"]');
const resultScreen = document.querySelector('[data-screen="result"]');
const renderScreen = document.querySelector('[data-screen="render"]');
const form = document.querySelector("#createForm");
const referenceInput = document.querySelector("#referenceInput");
const referenceField = document.querySelector(".reference-field");
const referencePreview = document.querySelector("#referencePreview");
const referenceName = document.querySelector("#referenceName");
const characterName = document.querySelector("#characterName");
const createButton = document.querySelector("#createButton");
const createError = document.querySelector("#createError");
const character = document.querySelector("#resultCharacter");
const resultStatus = document.querySelector("#resultStatus");
const commandButtons = [...document.querySelectorAll("[data-command]")];
const tabButtons = [...document.querySelectorAll("[data-tab]")];
const pipelineResults = document.querySelector("#pipelineResults");
const renderStage = document.querySelector("#renderStage");
const renderPercent = document.querySelector("#renderPercent");
const openComponent = document.querySelector("#openComponent");
const addAnimations = document.querySelector("#addAnimations");
const addAnimationsDialog = document.querySelector("#addAnimationsDialog");
const addAnimationsForm = document.querySelector("#addAnimationsForm");
const additionalMotions = document.querySelector("#additionalMotions");
const addAnimationsError = document.querySelector("#addAnimationsError");
const createdAnimationsCount = document.querySelector("#createdAnimationsCount");
const selectedAnimationsCount = document.querySelector("#selectedAnimationsCount");
const rerenderDialog = document.querySelector("#rerenderDialog");
const rerenderForm = document.querySelector("#rerenderForm");
const rerenderTitle = document.querySelector("#rerenderTitle");
const rerenderPrompt = document.querySelector("#rerenderPrompt");
const rerenderNegativePrompt = document.querySelector("#rerenderNegativePrompt");
const rerenderFrameCount = document.querySelector("#rerenderFrameCount");
const rerenderFrameValue = document.querySelector("#rerenderFrameValue");
const positiveTags = document.querySelector("#positiveTags");
const negativeTags = document.querySelector("#negativeTags");
const rerenderError = document.querySelector("#rerenderError");
const buildProgress = document.querySelector("#buildProgress");
const progressStage = document.querySelector("#progressStage");
const progressPercent = document.querySelector("#progressPercent");
const progressFill = document.querySelector("#progressFill");
const downloadPackage = document.querySelector("#downloadPackage");
const characterList = document.querySelector("#characterList");
const newCharacter = document.querySelector("#newCharacter");
const actionFieldset = document.querySelector("#actionFieldset");
const w3EditorDialog = document.querySelector("#w3EditorDialog");
const w3EditorCanvas = document.querySelector("#w3EditorCanvas");
const w3EditorTitle = document.querySelector("#w3EditorTitle");
const w3FrameLabel = document.querySelector("#w3FrameLabel");
const w3EditorStatus = document.querySelector("#w3EditorStatus");
const w3Undo = document.querySelector("#w3Undo");
const w3BrushSize = document.querySelector("#w3BrushSize");
const w3BrushValue = document.querySelector("#w3BrushValue");
const w3ZoomValue = document.querySelector("#w3ZoomValue");

const buildEndpoint = app.dataset.buildEndpoint || "/api/components";
let pollController = null;
let referencePreviewUrl = null;
let readyManifestUrl = null;
let rerenderAction = null;
let rerenderStage = "w1";
let selectedPromptTags = { positive: new Set(), negative: new Set() };
let currentPromptCatalog = null;
let currentPipelineActions = [];
let activeRerender = null;
let activeRerenderProgress = 0;
let currentPipelineItems = [];
let w3Edit = null;
let pipelineSignature = "";
let availableActionIds = new Set();
let idleCycleTimer = null;
let lastManualActionAt = Date.now();
let actionCatalog = [];
const collapsedPipelineActions = new Set();

const actionGroupLabels = {
  idle: "Idle",
  locomotion: "Передвижение",
  traversal: "Воздух и препятствия",
  combat: "Бой",
  interaction: "Взаимодействие",
  spells: "Спелы",
};

function renderActionOptions(actions) {
  actionCatalog = actions;
  actionFieldset.querySelectorAll(":scope > :not(legend)").forEach((node) => node.remove());
  const groups = new Map();
  for (const action of actions) {
    if (!groups.has(action.group)) groups.set(action.group, []);
    groups.get(action.group).push(action);
  }
  for (const [groupId, items] of groups) {
    const section = document.createElement("details");
    section.className = "action-option-group";
    section.open = groupId === "idle" || groupId === "locomotion";
    const heading = document.createElement("summary");
    heading.textContent = `${actionGroupLabels[groupId] || groupId} · ${items.length}`;
    const options = document.createElement("div");
    options.className = "action-option-grid";
    for (const action of items) {
      const label = document.createElement("label");
      label.className = "action-option";
      const input = document.createElement("input");
      input.type = "checkbox";
      input.name = "motion";
      input.value = action.id;
      input.checked = Boolean(action.default_selected);
      input.defaultChecked = input.checked;
      const copy = document.createElement("span");
      const title = document.createElement("strong");
      title.textContent = action.label;
      const id = document.createElement("small");
      id.textContent = action.id;
      copy.append(title, id);
      label.append(input, copy);
      options.append(label);
    }
    section.append(heading, options);
    actionFieldset.append(section);
  }
  actionFieldset.setAttribute("aria-busy", "false");
  createButton.disabled = false;
}

async function loadActionCatalog() {
  const payload = await readJson(await fetch("/api/component-actions", { cache: "no-store" }));
  renderActionOptions(payload.actions || []);
}

function renderPromptTags(catalog) {
  currentPromptCatalog = catalog;
  for (const [kind, container] of [["positive", positiveTags], ["negative", negativeTags]]) {
    container.replaceChildren();
    const tags = catalog.tags.filter((item) => item.kind === kind);
    const addTagButton = (tag, target) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "prompt-tag";
      button.textContent = `${tag.label}${tag.custom ? " ×" : ""}`;
      const sync = () => button.setAttribute("aria-pressed", String(selectedPromptTags[kind].has(tag.id)));
      button.addEventListener("click", () => {
        const selected = selectedPromptTags[kind];
        selected.has(tag.id) ? selected.delete(tag.id) : selected.add(tag.id);
        renderPromptTags(currentPromptCatalog);
      });
      sync();
      target.append(button);
    };
    tags.filter((tag) => selectedPromptTags[kind].has(tag.id)).forEach((tag) => addTagButton(tag, container));
    const details = document.createElement("details");
    details.className = "prompt-tag-picker";
    details.innerHTML = `<summary>+ Добавить тег</summary><div class="prompt-tag-options"></div>`;
    const options = details.querySelector(".prompt-tag-options");
    tags.filter((tag) => !selectedPromptTags[kind].has(tag.id)).forEach((tag) => addTagButton(tag, options));
    const custom = document.createElement("form");
    custom.className = "custom-tag-form";
    custom.innerHTML = `<input name="label" maxlength="60" placeholder="Название по-русски" required><input name="text" maxlength="1000" placeholder="Prompt in English" required><button type="submit">Добавить</button>`;
    custom.addEventListener("submit", async (event) => {
      event.preventDefault();
      const data = new FormData(custom);
      try {
        const tag = await readJson(await fetch("/api/prompt-tags", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ kind, label: data.get("label"), text: data.get("text") }),
        }));
        currentPromptCatalog.tags.push(tag);
        selectedPromptTags[kind].add(tag.id);
        renderPromptTags(currentPromptCatalog);
      } catch (error) {
        rerenderError.textContent = error.message;
        rerenderError.hidden = false;
      }
    });
    options.append(custom);
    container.append(details);
  }
}

async function openPromptEditor(item, code) {
  rerenderAction = item.id;
  rerenderStage = code.toLowerCase();
  rerenderTitle.textContent = `${item.label || item.id} · ${code}`;
  rerenderError.hidden = true;
  rerenderPrompt.value = "";
  rerenderNegativePrompt.value = "";
  const configuredFrames = item.frame_count || (item.id === "jump_up" ? 80 : 48);
  rerenderFrameCount.value = String(Math.max(8, Math.min(80, Math.round(configuredFrames / 4) * 4)));
  rerenderFrameValue.textContent = rerenderFrameCount.value;
  const query = new URLSearchParams({ action: rerenderAction, stage: rerenderStage });
  const catalog = await readJson(await fetch(`/api/prompt-tags?${query}`, { cache: "no-store" }));
  selectedPromptTags = {
    positive: new Set(catalog.defaults.positive),
    negative: new Set(catalog.defaults.negative),
  };
  renderPromptTags(catalog);
  rerenderDialog.showModal();
}

function getPipelineSignature(items = []) {
  return JSON.stringify(items.map((item) => [
    item.id,
    item.status,
    item.w1,
    item.w2,
    item.w3,
    item.frame_count,
    item.fps,
  ]));
}

function selectTab(name) {
  for (const screen of [charactersScreen, createScreen, renderScreen, resultScreen]) {
    screen.hidden = screen.dataset.screen !== name;
  }
  tabButtons.forEach((button) => {
    button.toggleAttribute("aria-current", button.dataset.tab === name);
  });
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function syncCommandButtons({ busy = false } = {}) {
  commandButtons.forEach((button) => {
    const bound = availableActionIds.has(button.dataset.command);
    button.disabled = busy || !bound;
    button.classList.toggle("unbound", !bound);
    button.title = bound ? "" : "Анимация ещё не создана";
  });
}

function startIdleCycle() {
  window.clearInterval(idleCycleTimer);
  const idleActions = [...availableActionIds].filter((id) => id === "idle" || id.startsWith("idle_"));
  if (idleActions.length < 2) return;
  idleCycleTimer = window.setInterval(() => {
    if (Date.now() - lastManualActionAt < 7000 || document.hidden) return;
    const currentIndex = Math.max(0, idleActions.indexOf(character.currentAction));
    const next = idleActions[(currentIndex + 1) % idleActions.length];
    character.play(next, { interrupt: "immediate" }).catch(() => {});
  }, 7000);
}

async function openStoredCharacter(componentId) {
  const url = new URL(window.location.href);
  url.searchParams.set("component", componentId);
  url.searchParams.delete("manifest");
  window.history.replaceState({}, "", url);
  unlockTab("render", true);
  selectTab("render");
  const statusUrl = `/api/components/${encodeURIComponent(componentId)}`;
  try {
    const manifestUrl = await waitForComponent(statusUrl);
    readyManifestUrl = manifestUrl;
    openComponent.disabled = false;
    unlockTab("result", true);
    renderStage.textContent = "Все выбранные анимации готовы";
    renderPercent.textContent = "100%";
  } catch (error) {
    renderStage.textContent = error.message;
    renderPercent.textContent = "Ошибка";
  }
}

async function loadCharacterLibrary() {
  characterList.innerHTML = '<span class="library-status">Загружаем…</span>';
  try {
    const payload = await readJson(await fetch("/api/studio/projects", { cache: "no-store" }));
    const projects = payload.projects || [];
    const entries = await Promise.all(projects.map(async (project) => {
      try {
        const status = await readJson(await fetch(`/api/components/${encodeURIComponent(project.id)}`, { cache: "no-store" }));
        return { project, status };
      } catch {
        return { project, status: null };
      }
    }));
    characterList.replaceChildren();
    if (!entries.length) {
      characterList.innerHTML = '<span class="library-status">Персонажей пока нет</span>';
      return;
    }
    for (const { project, status } of entries) {
      const card = document.createElement("article");
      card.className = `character-card ${status ? "available" : "incomplete"}`;
      if (project.primary_asset_id) {
        const image = document.createElement("img");
        image.src = `/studio-media/${encodeURIComponent(project.id)}/${encodeURIComponent(project.primary_asset_id)}`;
        image.alt = "";
        card.append(image);
      }
      const info = document.createElement("div");
      const date = project.updated_at ? new Date(project.updated_at).toLocaleString("ru-RU", { dateStyle: "short", timeStyle: "short" }) : "";
      const title = document.createElement("strong");
      title.textContent = project.name || project.id;
      const details = document.createElement("small");
      details.textContent = `${status ? (status.status === "ready" ? "Готов" : "В работе") : "Без анимаций"}${date ? ` · ${date}` : ""}`;
      info.append(title, details);
      card.append(info);
      const open = document.createElement("button");
      open.type = "button";
      open.textContent = status ? "Открыть" : "Нет рендера";
      open.disabled = !status;
      if (status) open.addEventListener("click", () => openStoredCharacter(project.id));
      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "delete-character";
      remove.textContent = "×";
      remove.title = `Удалить ${project.name || project.id}`;
      remove.setAttribute("aria-label", `Удалить персонажа ${project.name || project.id}`);
      remove.addEventListener("click", async () => {
        if (!window.confirm(`Удалить персонажа «${project.name || project.id}» и все его анимации?`)) return;
        remove.disabled = true;
        try {
          await readJson(await fetch(`/api/components/${encodeURIComponent(project.id)}`, { method: "DELETE" }));
          card.remove();
          if (!characterList.querySelector(".character-card")) {
            characterList.innerHTML = '<span class="library-status">Персонажей пока нет</span>';
          }
        } catch (error) {
          remove.disabled = false;
          window.alert(error.message);
        }
      });
      const controls = document.createElement("div");
      controls.className = "character-card-controls";
      controls.append(open, remove);
      card.append(controls);
      characterList.append(card);
    }
  } catch (error) {
    characterList.innerHTML = `<span class="library-status">${error.message}</span>`;
  }
}

function unlockTab(name, unlocked = true) {
  const button = tabButtons.find((item) => item.dataset.tab === name);
  if (button) button.disabled = !unlocked;
}

function renderPipeline(items = []) {
  pipelineSignature = getPipelineSignature(items);
  currentPipelineItems = items;
  currentPipelineActions = items.map((item) => item.id);
  pipelineResults.replaceChildren();
  for (const item of items) {
    const row = document.createElement("article");
    row.className = "pipeline-action";
    const title = document.createElement("h2");
    title.textContent = item.label || item.id;
    const actionHeading = document.createElement("div");
    actionHeading.className = "pipeline-action-heading";
    const collapse = document.createElement("button");
    collapse.type = "button";
    collapse.className = "pipeline-collapse";
    const collapsed = collapsedPipelineActions.has(item.id);
    collapse.textContent = collapsed ? "▸" : "▾";
    collapse.title = collapsed ? "Развернуть" : "Свернуть";
    collapse.setAttribute("aria-label", `${collapsed ? "Развернуть" : "Свернуть"}: ${item.label || item.id}`);
    collapse.setAttribute("aria-expanded", String(!collapsed));
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "pipeline-delete";
    remove.textContent = "Удалить";
    remove.disabled = items.length <= 1;
    remove.title = remove.disabled ? "Нельзя удалить последнюю анимацию" : "Удалить эту анимацию";
    remove.setAttribute("aria-label", `Удалить анимацию: ${item.label || item.id}`);
    remove.addEventListener("click", async () => {
      const componentId = new URL(window.location.href).searchParams.get("component");
      if (!componentId || !window.confirm(`Удалить анимацию «${item.label || item.id}»? Остальные анимации останутся без изменений.`)) return;
      remove.disabled = true;
      try {
        const response = await readJson(await fetch(
          `/api/components/${encodeURIComponent(componentId)}/actions/${encodeURIComponent(item.id)}`,
          { method: "DELETE" },
        ));
        collapsedPipelineActions.delete(item.id);
        renderPipeline(response.pipeline || []);
        readyManifestUrl = response.manifest_url || null;
        availableActionIds.delete(item.id);
        syncCommandButtons();
      } catch (error) {
        remove.disabled = false;
        window.alert(error.message);
      }
    });
    actionHeading.append(collapse, title, remove);
    row.append(actionHeading);
    const chain = document.createElement("div");
    chain.className = "pipeline-chain";
    chain.hidden = collapsed;
    row.classList.toggle("collapsed", collapsed);
    collapse.addEventListener("click", () => {
      const nextCollapsed = !chain.hidden;
      chain.hidden = nextCollapsed;
      row.classList.toggle("collapsed", nextCollapsed);
      collapse.textContent = nextCollapsed ? "▸" : "▾";
      collapse.title = nextCollapsed ? "Развернуть" : "Свернуть";
      collapse.setAttribute("aria-expanded", String(!nextCollapsed));
      if (nextCollapsed) collapsedPipelineActions.add(item.id);
      else collapsedPipelineActions.delete(item.id);
    });
    const stages = [
      ["W1", "Ключевой кадр", "image", item.w1],
      ["W2", "Видео", "video", item.w2],
      ["W3", "Анимация", "runtime", item.w3],
    ];
    stages.forEach(([code, label, kind, src], index) => {
      const stage = document.createElement("section");
      stage.className = `pipeline-stage ${src ? "ready" : "pending"}`;
      stage.dataset.action = item.id;
      stage.dataset.stage = code.toLowerCase();
      const heading = document.createElement("div");
      heading.innerHTML = `<strong>${code}</strong><span>${label}</span>`;
      const size = document.createElement("small");
      size.className = "stage-size";
      size.textContent = src ? "Определяем размер…" : "—";
      heading.append(size);
      if (kind !== "runtime") {
        const edit = document.createElement("button");
        edit.type = "button";
        edit.className = "stage-edit";
        edit.textContent = "✎";
        edit.title = `Перезапустить ${code}`;
        edit.setAttribute("aria-label", `Настроить и перезапустить ${code}: ${item.label || item.id}`);
        edit.addEventListener("click", () => openPromptEditor(item, code).catch((error) => {
          rerenderError.textContent = error.message;
          rerenderError.hidden = false;
        }));
        heading.append(edit);
      } else if (src) {
        const edit = document.createElement("button");
        edit.type = "button";
        edit.className = "stage-edit";
        edit.textContent = "✎";
        edit.title = "Очистить фон W3";
        edit.setAttribute("aria-label", `Открыть постобработку W3: ${item.label || item.id}`);
        edit.addEventListener("click", () => openW3Editor(item));
        heading.append(edit);
      }
      stage.append(heading);
      const media = document.createElement("div");
      media.className = `stage-media ${kind}`;
      const rerenderStart = activeRerender ? ["w1", "w2", "w3"].indexOf(activeRerender.stage) : -1;
      const isAffectedByRerender = activeRerender?.action === item.id && index >= rerenderStart && rerenderStart >= 0;
      const isRerendering = isAffectedByRerender && index === rerenderStart;
      if (isRerendering) {
        media.classList.add("rerendering");
        const loader = document.createElement("div");
        loader.className = "stage-loader";
        const operation = activeRerender.initial ? "Рендер" : "Перегенерация";
        loader.innerHTML = `<span class="stage-spinner" aria-hidden="true"></span><strong>${Math.round(activeRerenderProgress)}%</strong><small>${operation} ${code}</small>`;
        media.append(loader);
        size.textContent = `${Math.round(activeRerenderProgress)}%`;
      } else if (isAffectedByRerender) {
        media.classList.add("rerendering");
        const pending = document.createElement("div");
        pending.className = "stage-loader pending-stage";
        pending.innerHTML = `<strong>…</strong><small>Обновится после ${activeRerender.stage.toUpperCase()}</small>`;
        media.append(pending);
        size.textContent = "ожидает";
      } else if (src && kind === "video") {
        const video = document.createElement("video");
        video.src = absoluteUrl(src);
        video.controls = true;
        video.loop = true;
        video.muted = true;
        video.playsInline = true;
        video.addEventListener("loadedmetadata", () => {
          size.textContent = `${video.videoWidth}x${video.videoHeight}`;
        }, { once: true });
        media.append(video);
      } else if (src && kind === "runtime") {
        const preview = document.createElement("animated-character");
        preview.setAttribute("idle", "preview");
        media.append(preview);
        const probe = new Image();
        probe.addEventListener("load", () => {
          const frameCount = Number(item.frame_count) || 1;
          size.textContent = `${probe.naturalWidth}x${probe.naturalHeight} (${frameCount} кадров)`;
        }, { once: true });
        probe.src = absoluteUrl(src);
        preview.load({
          id: `${item.id}-w3-preview`,
          base_url: window.location.href,
          canvas: { width: 512, height: 512 },
          default_action: "preview",
          actions: {
            preview: {
              src: absoluteUrl(src),
              frame_count: Number(item.frame_count) || 1,
              fps: Number(item.fps) || 12,
              playback: "loop",
            },
          },
        }).catch(() => {
          size.textContent = "Не удалось открыть W3";
        });
      } else if (src) {
        const image = document.createElement("img");
        image.src = absoluteUrl(src);
        image.alt = `${code}: ${label}`;
        image.addEventListener("load", () => {
          size.textContent = `${image.naturalWidth}x${image.naturalHeight}`;
        }, { once: true });
        media.append(image);
      } else {
        media.textContent = "Ожидает рендера";
      }
      stage.append(media);
      chain.append(stage);
      if (index < stages.length - 1) {
        const arrow = document.createElement("span");
        arrow.className = "pipeline-arrow";
        arrow.textContent = "→";
        chain.append(arrow);
      }
    });
    row.append(chain);
    pipelineResults.append(row);
  }
}

function setError(message = "") {
  createError.textContent = message;
  createError.hidden = !message;
}

function setBusy(busy, label = "Создать персонажа") {
  createButton.disabled = busy;
  createButton.textContent = label;
  referenceInput.disabled = busy;
  form.querySelectorAll('input[name="motion"]').forEach((input) => {
    input.disabled = busy;
  });
}

function setBuildProgress(value, stage, { error = false } = {}) {
  const percent = Math.max(0, Math.min(100, Number(value) || 0));
  buildProgress.hidden = false;
  buildProgress.classList.toggle("error", error);
  buildProgress.setAttribute("aria-valuenow", String(Math.round(percent)));
  progressStage.textContent = formatStageLabel(stage || "Создаём персонажа");
  progressPercent.textContent = `${Math.round(percent)}%`;
  progressFill.style.width = `${percent}%`;
}

function formatStageLabel(value) {
  return String(value || "").replace(/(W[123]\s*·\s*[^:]+)\s+\d+%:/i, "$1:");
}

function absoluteUrl(value) {
  return new URL(value, window.location.href).href;
}

function renderW3Frame() {
  if (!w3Edit) return;
  const ctx = w3EditorCanvas.getContext("2d", { willReadFrequently: true });
  ctx.clearRect(0, 0, 512, 512);
  ctx.drawImage(w3Edit.frames[w3Edit.frame], 0, 0);
  w3FrameLabel.textContent = `Кадр ${w3Edit.frame + 1} / ${w3Edit.frameCount}`;
  w3Undo.disabled = w3Edit.undo.length === 0;
  renderW3Timeline();
}

function commitW3Frame() {
  if (!w3Edit) return;
  const frame = w3Edit.frames[w3Edit.frame];
  const ctx = frame.getContext("2d", { willReadFrequently: true });
  ctx.clearRect(0, 0, 512, 512);
  ctx.drawImage(w3EditorCanvas, 0, 0);
}

function createW3Frame(source = null) {
  const frame = document.createElement("canvas");
  frame.width = 512;
  frame.height = 512;
  if (source) frame.getContext("2d").drawImage(source, 0, 0, 512, 512);
  return frame;
}

function renderW3Timeline() {
  if (!w3Edit) return;
  const timeline = document.querySelector("#w3Timeline");
  timeline.replaceChildren();
  w3Edit.frames.forEach((frame, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "w3-timeline-frame";
    button.toggleAttribute("aria-current", index === w3Edit.frame);
    button.title = `Кадр ${index + 1}`;
    const preview = document.createElement("canvas");
    preview.width = 72;
    preview.height = 72;
    preview.getContext("2d").drawImage(frame, 0, 0, 72, 72);
    const number = document.createElement("span");
    number.textContent = String(index + 1);
    button.append(preview, number);
    button.addEventListener("click", () => {
      commitW3Frame();
      w3Edit.frame = index;
      renderW3Frame();
      button.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" });
    });
    timeline.append(button);
  });
}

function setW3Frames(frames, selected) {
  if (!w3Edit || !frames.length) return;
  w3Edit.frames = frames;
  w3Edit.frameCount = frames.length;
  w3Edit.frame = Math.max(0, Math.min(frames.length - 1, selected));
  w3Edit.undo = [];
  renderW3Frame();
}

function pushW3Undo() {
  if (!w3Edit) return;
  const ctx = w3EditorCanvas.getContext("2d", { willReadFrequently: true });
  w3Edit.undo.push({ frame: w3Edit.frame, pixels: ctx.getImageData(0, 0, 512, 512) });
  if (w3Edit.undo.length > 30) w3Edit.undo.shift();
  w3Undo.disabled = false;
}

function removeConnectedArea(x, y) {
  const ctx = w3EditorCanvas.getContext("2d", { willReadFrequently: true });
  const image = ctx.getImageData(0, 0, 512, 512);
  const data = image.data;
  const start = (y * 512 + x) * 4;
  const target = [data[start], data[start + 1], data[start + 2], data[start + 3]];
  if (target[3] === 0) return;
  pushW3Undo();
  const seen = new Uint8Array(512 * 512);
  const queue = new Int32Array(512 * 512);
  let head = 0;
  let tail = 0;
  queue[tail++] = y * 512 + x;
  seen[y * 512 + x] = 1;
  const tolerance = 34;
  while (head < tail) {
    const index = queue[head++];
    const offset = index * 4;
    const distance = Math.max(
      Math.abs(data[offset] - target[0]),
      Math.abs(data[offset + 1] - target[1]),
      Math.abs(data[offset + 2] - target[2]),
    );
    if (distance > tolerance || data[offset + 3] === 0) continue;
    data[offset + 3] = 0;
    const px = index % 512;
    const py = Math.floor(index / 512);
    for (const next of [index - 1, index + 1, index - 512, index + 512]) {
      if (next < 0 || next >= seen.length || seen[next]) continue;
      const nx = next % 512;
      const ny = Math.floor(next / 512);
      if (Math.abs(nx - px) + Math.abs(ny - py) !== 1) continue;
      seen[next] = 1;
      queue[tail++] = next;
    }
  }
  ctx.putImageData(image, 0, 0);
  commitW3Frame();
}

function setW3Zoom(value) {
  if (!w3Edit) return;
  w3Edit.zoom = Math.max(0.5, Math.min(4, value));
  w3EditorCanvas.style.width = `${512 * w3Edit.zoom}px`;
  w3EditorCanvas.style.height = `${512 * w3Edit.zoom}px`;
  w3ZoomValue.textContent = `${Math.round(w3Edit.zoom * 100)}%`;
}

async function openW3Editor(item) {
  w3EditorStatus.textContent = "Загрузка…";
  w3EditorTitle.textContent = item.label || item.id;
  w3EditorDialog.showModal();
  try {
    const image = new Image();
    image.crossOrigin = "anonymous";
    await new Promise((resolve, reject) => {
      image.onload = resolve;
      image.onerror = () => reject(new Error("Не удалось открыть W3"));
      image.src = `${absoluteUrl(item.w3)}?edit=${Date.now()}`;
    });
    const frameCount = Number(item.frame_count) || Math.floor(image.naturalWidth / 512);
    const frames = Array.from({ length: frameCount }, (_, index) => {
      const frame = createW3Frame();
      frame.getContext("2d").drawImage(image, index * 512, 0, 512, 512, 0, 0, 512, 512);
      return frame;
    });
    w3Edit = {
      action: item.id,
      frame: 0,
      frameCount,
      frames,
      fps: Number(item.fps) || 12,
      undo: [],
      tool: "fill",
      zoom: 1,
      drawing: false,
      playing: false,
      playTimer: null,
      uploadMode: "replace",
    };
    setW3Zoom(1);
    renderW3Frame();
    w3EditorStatus.textContent = "Кликните по фону или выберите ластик";
  } catch (error) {
    w3EditorStatus.textContent = error.message;
  }
}

async function readJson(response) {
  const type = response.headers.get("content-type") || "";
  const payload = type.includes("application/json") ? await response.json() : null;
  if (!response.ok) {
    const error = new Error(payload?.error || `${response.status} ${response.statusText}`);
    error.status = response.status;
    throw error;
  }
  return payload;
}

function isRetryableStatusError(error) {
  const status = Number(error?.status) || 0;
  return status === 0 || status === 408 || status === 429 || status >= 500;
}

function wait(milliseconds, signal) {
  return new Promise((resolve, reject) => {
    const timer = window.setTimeout(resolve, milliseconds);
    signal?.addEventListener("abort", () => {
      window.clearTimeout(timer);
      reject(new DOMException("Polling stopped", "AbortError"));
    }, { once: true });
  });
}

async function waitForComponent(statusUrl) {
  pollController?.abort();
  pollController = new AbortController();
  const { signal } = pollController;
  let consecutivePollFailures = 0;
  while (!signal.aborted) {
    let status;
    try {
      status = await readJson(await fetch(absoluteUrl(statusUrl), {
        cache: "no-store",
        signal,
      }));
      consecutivePollFailures = 0;
    } catch (error) {
      if (signal.aborted || error.name === "AbortError") throw error;
      if (!isRetryableStatusError(error)) throw error;
      consecutivePollFailures += 1;
      if (consecutivePollFailures >= 120) throw error;
      renderStage.textContent = `Восстанавливаем связь с сервером · попытка ${consecutivePollFailures}…`;
      const retryDelay = Math.min(5000, 1000 * (2 ** Math.min(3, consecutivePollFailures - 1)));
      await wait(retryDelay, signal);
      continue;
    }
    if (!activeRerender && status.rerender?.action && status.rerender?.stage) {
      activeRerender = {
        action: status.rerender.action,
        stage: status.rerender.stage,
      };
    }
    if (status.active?.action && status.active?.stage) {
      const changed = activeRerender?.action !== status.active.action
        || activeRerender?.stage !== status.active.stage
        || !activeRerender?.initial;
      activeRerender = { ...status.active, initial: true };
      if (changed) renderPipeline(status.pipeline || []);
    }
    if (!activeRerender && status.status === "running") {
      const stageText = String(status.stage || "");
      const stageMatch = stageText.match(/^W([123])\b/i);
      const inferredStage = stageMatch ? `w${stageMatch[1]}` : stageText.startsWith("Создаём:") ? "w1" : null;
      const inferredItem = (status.pipeline || []).find((item) => stageText.includes(item.label || item.id));
      if (inferredStage && inferredItem) {
        activeRerender = { action: inferredItem.id, stage: inferredStage, initial: true };
        renderPipeline(status.pipeline || []);
      }
    }
    const nextProgress = Math.max(0, Math.min(100, Number(status.progress) || 0));
    const sameActiveStage = activeRerender
      && activeRerender.action === (status.active?.action || status.rerender?.action || activeRerender.action)
      && activeRerender.stage === (status.active?.stage || status.rerender?.stage || activeRerender.stage);
    activeRerenderProgress = sameActiveStage
      ? Math.max(activeRerenderProgress, nextProgress)
      : nextProgress;
    const terminalReady = ["ready", "succeeded", "complete", "completed"].includes(status.status);
    if (terminalReady) {
      activeRerender = null;
    }
    if (activeRerender) {
      const selector = `.pipeline-stage[data-action="${CSS.escape(activeRerender.action)}"][data-stage="${CSS.escape(activeRerender.stage)}"]`;
      let stage = pipelineResults.querySelector(selector);
      if (!stage) {
        renderPipeline(status.pipeline || []);
        stage = pipelineResults.querySelector(selector);
      }
      if (stage) {
        const percent = `${Math.round(activeRerenderProgress)}%`;
        const loaderPercent = stage.querySelector(".stage-loader strong");
        const stageSize = stage.querySelector(".stage-size");
        if (loaderPercent) loaderPercent.textContent = percent;
        if (stageSize) stageSize.textContent = percent;
      }
    } else {
      const nextPipeline = status.pipeline || [];
      if (getPipelineSignature(nextPipeline) !== pipelineSignature) {
        renderPipeline(nextPipeline);
      }
    }
    renderStage.textContent = formatStageLabel(status.stage || status.message || "Рендерим");
    renderPercent.textContent = `${Math.round(Number(status.progress) || 0)}%`;
    if (["ready", "succeeded", "complete", "completed"].includes(status.status)) {
      if (!status.manifest_url) throw new Error("Готовый компонент не содержит manifest_url");
      setBuildProgress(100, status.stage || "Компонент готов");
      return status.manifest_url;
    }
    if (["failed", "error", "cancelled", "canceled"].includes(status.status)) {
      throw new Error(status.error || "Не удалось создать персонажа");
    }
    const percent = Number(status.progress);
    const label = Number.isFinite(percent)
      ? `Создаём персонажа · ${Math.round(percent)}%`
      : "Создаём персонажа…";
    setBuildProgress(Number.isFinite(percent) ? percent : 2, status.stage || status.message);
    setBusy(true, label);
    await wait(1000, signal);
  }
  throw new DOMException("Polling stopped", "AbortError");
}

async function showResult(manifestUrl) {
  readyManifestUrl = manifestUrl;
  unlockTab("result", true);
  selectTab("result");
  resultStatus.hidden = false;
  resultStatus.textContent = "Загрузка персонажа…";
  availableActionIds = new Set();
  syncCommandButtons({ busy: true });
  await character.load(absoluteUrl(manifestUrl));
  resultStatus.hidden = true;
  availableActionIds = new Set(Object.keys(character.manifest?.actions || {}));
  syncCommandButtons();
  lastManualActionAt = Date.now();
  startIdleCycle();
  const componentId = new URL(window.location.href).searchParams.get("component");
  if (componentId) {
    downloadPackage.href = `/api/components/${encodeURIComponent(componentId)}/package`;
    downloadPackage.hidden = false;
  }
  const url = new URL(window.location.href);
  url.searchParams.set("manifest", manifestUrl);
  window.history.replaceState({}, "", url);
}

function showCreate() {
  pollController?.abort();
  selectTab("create");
  setBusy(false);
  const url = new URL(window.location.href);
  url.searchParams.delete("manifest");
  url.searchParams.delete("component");
  window.history.replaceState({}, "", url);
  window.scrollTo({ top: 0, behavior: "smooth" });
}

document.querySelectorAll("[data-go]").forEach((button) => {
  button.addEventListener("click", () => selectTab(button.dataset.go));
});

tabButtons.forEach((button) => {
  button.addEventListener("click", async () => {
    if (!button.disabled) {
      selectTab(button.dataset.tab);
      if (button.dataset.tab === "characters") loadCharacterLibrary();
      if (button.dataset.tab === "result" && readyManifestUrl) {
        try {
          await showResult(readyManifestUrl);
        } catch (error) {
          resultStatus.textContent = error.message;
          resultStatus.hidden = false;
        }
      }
    }
  });
});

newCharacter.addEventListener("click", () => {
  pollController?.abort();
  form.reset();
  setBusy(false);
  characterName.value = "";
  referencePreview.hidden = true;
  referencePreview.removeAttribute("src");
  referenceName.textContent = "PNG, JPG или WEBP";
  referenceField.classList.remove("has-preview");
  buildProgress.hidden = true;
  setError();
  const url = new URL(window.location.href);
  url.searchParams.delete("component");
  url.searchParams.delete("manifest");
  window.history.replaceState({}, "", url);
  selectTab("create");
});

referenceField.addEventListener("click", (event) => {
  if (event.target === referenceInput || referenceInput.disabled) return;
  event.preventDefault();
  referenceInput.click();
});

openComponent.addEventListener("click", () => {
  if (readyManifestUrl) showResult(readyManifestUrl);
});

function updateAdditionalAnimationSelection() {
  const selected = additionalMotions.querySelectorAll('input[name="additional-motion"]:checked:not(:disabled)').length;
  const submit = addAnimationsForm.querySelector('[type="submit"]');
  selectedAnimationsCount.textContent = `Выбрано: ${selected}`;
  submit.disabled = selected === 0;
  submit.textContent = selected ? `Добавить выбранные · ${selected}` : "Добавить выбранные";
  if (selected) addAnimationsError.hidden = true;
}

function openAddAnimationsDialog() {
  additionalMotions.replaceChildren();
  const legend = document.createElement("legend");
  legend.className = "sr-only";
  legend.textContent = "Доступные анимации";
  additionalMotions.append(legend);
  const groups = new Map();
  for (const action of actionCatalog) {
    if (!groups.has(action.group)) groups.set(action.group, []);
    groups.get(action.group).push(action);
  }
  const created = actionCatalog.filter((action) => currentPipelineActions.includes(action.id)).length;
  createdAnimationsCount.textContent = `Создано: ${created} из ${actionCatalog.length}`;
  let available = 0;
  for (const [groupId, actions] of groups) {
    const group = document.createElement("details");
    group.className = "animation-picker-group";
    group.open = groupId === "idle" || groupId === "locomotion";
    const groupCreated = actions.filter((action) => currentPipelineActions.includes(action.id)).length;
    const summary = document.createElement("summary");
    const groupTitle = document.createElement("strong");
    groupTitle.textContent = actionGroupLabels[groupId] || groupId;
    const groupStatus = document.createElement("small");
    groupStatus.textContent = `${actions.length - groupCreated} новых · ${groupCreated} создано`;
    summary.append(groupTitle, groupStatus);
    const grid = document.createElement("div");
    grid.className = "animation-picker-grid";
    for (const action of actions) {
      const alreadyCreated = currentPipelineActions.includes(action.id);
      if (!alreadyCreated) available += 1;
      const option = document.createElement("label");
      option.className = "animation-choice";
      option.classList.toggle("already-created", alreadyCreated);
      const input = document.createElement("input");
      input.type = "checkbox";
      input.name = "additional-motion";
      input.value = action.id;
      input.checked = alreadyCreated;
      input.disabled = alreadyCreated;
      input.addEventListener("change", updateAdditionalAnimationSelection);
      const check = document.createElement("span");
      check.className = "animation-choice-check";
      check.setAttribute("aria-hidden", "true");
      check.textContent = "✓";
      const copy = document.createElement("span");
      copy.className = "animation-choice-copy";
      const title = document.createElement("strong");
      title.textContent = action.label;
      const status = document.createElement("small");
      status.textContent = alreadyCreated ? "Создано" : "Можно добавить";
      copy.append(title, status);
      option.append(input, check, copy);
      grid.append(option);
    }
    group.append(summary, grid);
    additionalMotions.append(group);
  }
  if (!available) {
    const empty = document.createElement("p");
    empty.className = "animation-picker-empty";
    empty.textContent = "Все доступные анимации уже созданы.";
    additionalMotions.append(empty);
  }
  updateAdditionalAnimationSelection();
  addAnimationsError.hidden = true;
  addAnimationsDialog.showModal();
}

addAnimations.addEventListener("click", openAddAnimationsDialog);
document.querySelector("[data-close-add-animations]").addEventListener("click", () => addAnimationsDialog.close());
addAnimationsForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const selected = [...additionalMotions.querySelectorAll('input[name="additional-motion"]:checked:not(:disabled)')]
    .map((input) => input.value);
  if (!selected.length) {
    addAnimationsError.textContent = "Выберите хотя бы одну новую анимацию.";
    addAnimationsError.hidden = false;
    return;
  }
  const componentId = new URL(window.location.href).searchParams.get("component");
  if (!componentId) {
    addAnimationsError.textContent = "Не удалось определить персонажа.";
    addAnimationsError.hidden = false;
    return;
  }
  const submit = addAnimationsForm.querySelector('[type="submit"]');
  submit.disabled = true;
  try {
    const actions = [...new Set([...currentPipelineActions, ...selected])];
    const response = await readJson(await fetch(`/api/components/${encodeURIComponent(componentId)}/rebuild`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        actions,
        rerun_action: "",
        start_step: "w1",
        force: false,
      }),
    }));
    addAnimationsDialog.close();
    readyManifestUrl = null;
    openComponent.disabled = true;
    unlockTab("result", false);
    renderPipeline(actions.map((id) => currentPipelineItems.find((item) => item.id === id) || {
      id,
      label: id,
      status: "pending",
    }));
    selectTab("render");
    readyManifestUrl = await waitForComponent(response.status_url);
    openComponent.disabled = false;
    unlockTab("result", true);
    renderStage.textContent = "Все выбранные анимации готовы";
    renderPercent.textContent = "100%";
  } catch (error) {
    addAnimationsError.textContent = error.message;
    addAnimationsError.hidden = false;
    if (!addAnimationsDialog.open) addAnimationsDialog.showModal();
  } finally {
    submit.disabled = false;
  }
});

document.querySelector("[data-close-dialog]").addEventListener("click", () => rerenderDialog.close());
rerenderFrameCount.addEventListener("input", () => {
  rerenderFrameValue.textContent = rerenderFrameCount.value;
});

rerenderForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const componentId = new URL(window.location.href).searchParams.get("component");
  if (!componentId || !rerenderAction) return;
  const submit = rerenderForm.querySelector('[type="submit"]');
  submit.disabled = true;
  rerenderError.hidden = true;
  try {
    const response = await readJson(await fetch(`/api/components/${encodeURIComponent(componentId)}/rebuild`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        actions: currentPipelineActions,
        rerun_action: rerenderAction,
        start_step: rerenderStage,
        positive_tags: [...selectedPromptTags.positive],
        custom_positive: rerenderPrompt.value.trim(),
        extra_prompt: "",
        negative_tags: [...selectedPromptTags.negative],
        custom_negative: rerenderNegativePrompt.value.trim(),
        frame_count: Number(rerenderFrameCount.value),
        force: true,
      }),
    }));
    rerenderDialog.close();
    activeRerender = { action: rerenderAction, stage: rerenderStage };
    activeRerenderProgress = 0;
    renderPipeline(currentPipelineItems);
    readyManifestUrl = null;
    openComponent.disabled = true;
    unlockTab("result", false);
    await waitForComponent(response.status_url);
    readyManifestUrl = `/api/components/${encodeURIComponent(componentId)}/manifest`;
    openComponent.disabled = false;
    unlockTab("result", true);
  } catch (error) {
    activeRerender = null;
    renderPipeline(currentPipelineItems);
    rerenderError.textContent = error.message;
    rerenderError.hidden = false;
  } finally {
    submit.disabled = false;
  }
});

referenceInput.addEventListener("change", () => {
  const file = referenceInput.files[0];
  if (referencePreviewUrl) URL.revokeObjectURL(referencePreviewUrl);
  referencePreviewUrl = file ? URL.createObjectURL(file) : null;
  referencePreview.hidden = !referencePreviewUrl;
  referencePreview.removeAttribute("src");
  if (referencePreviewUrl) referencePreview.src = referencePreviewUrl;
  referenceField.classList.toggle("has-preview", Boolean(referencePreviewUrl));
  referenceName.textContent = file?.name || "PNG, JPG или WEBP";
  setError();
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  setError();
  const reference = referenceInput.files[0];
  const name = characterName.value.trim();
  const motions = [...form.querySelectorAll('input[name="motion"]:checked')].map((input) => input.value);
  if (!reference) {
    setError("Выберите изображение персонажа.");
    return;
  }
  if (!name) {
    setError("Укажите имя персонажа.");
    return;
  }
  if (!motions.length) {
    setError("Выберите хотя бы одно действие.");
    return;
  }

  setBusy(true, "Загружаем референс…");
  setBuildProgress(1, "Загружаем референс");
  readyManifestUrl = null;
  openComponent.disabled = true;
  unlockTab("render", true);
  unlockTab("result", false);
  renderPipeline(motions.map((id) => ({ id, label: id, status: "pending" })));
  selectTab("render");
  try {
    const data = new FormData();
    data.append("name", name);
    data.append("reference", reference, reference.name);
    motions.forEach((motion) => data.append("motion", motion));
    const created = await readJson(await fetch(absoluteUrl(buildEndpoint), {
      method: "POST",
      body: data,
    }));
    const currentUrl = new URL(window.location.href);
    currentUrl.searchParams.set("component", created.id);
    currentUrl.searchParams.delete("manifest");
    window.history.replaceState({}, "", currentUrl);
    const manifestUrl = created.manifest_url
      ?? await waitForComponent(created.status_url ?? `/api/components/${encodeURIComponent(created.id)}`);
    readyManifestUrl = manifestUrl;
    openComponent.disabled = false;
    unlockTab("result", true);
    renderStage.textContent = "Все выбранные анимации готовы";
    renderPercent.textContent = "100%";
  } catch (error) {
    if (error.name !== "AbortError") {
      setError(error.message);
      renderStage.textContent = error.message;
    }
    if (error.name !== "AbortError") setBuildProgress(
      Number(buildProgress.getAttribute("aria-valuenow")),
      "Сборка остановлена",
      { error: true },
    );
    setBusy(false);
  }
});

commandButtons.forEach((button) => {
  button.setAttribute("aria-pressed", "false");
  button.addEventListener("click", async () => {
    lastManualActionAt = Date.now();
    syncCommandButtons({ busy: true });
    try {
      await character.play(button.dataset.command, { interrupt: "immediate" });
    } catch (error) {
      resultStatus.textContent = error.message;
      resultStatus.hidden = false;
    } finally {
      syncCommandButtons();
    }
  });
});

character.addEventListener("motionstart", (event) => {
  commandButtons.forEach((button) => {
    button.setAttribute("aria-pressed", String(button.dataset.command === event.detail.actionId));
  });
});

character.addEventListener("charactererror", (event) => {
  resultStatus.textContent = event.detail.message || "Не удалось загрузить персонажа";
  resultStatus.hidden = false;
});

window.addEventListener("beforeunload", () => {
  window.clearInterval(idleCycleTimer);
  pollController?.abort();
  if (referencePreviewUrl) URL.revokeObjectURL(referencePreviewUrl);
}, { once: true });

function stopW3Playback() {
  if (!w3Edit) return;
  window.clearInterval(w3Edit.playTimer);
  w3Edit.playTimer = null;
  w3Edit.playing = false;
  const button = document.querySelector("#w3AutoPlay");
  button.textContent = "▶ Автопрокрутка";
  button.setAttribute("aria-pressed", "false");
}

document.querySelector("#w3EditorClose").addEventListener("click", () => {
  stopW3Playback();
  w3EditorDialog.close();
});
w3EditorDialog.addEventListener("close", stopW3Playback);
document.querySelectorAll("[data-editor-tool]").forEach((button) => {
  button.addEventListener("click", () => {
    if (!w3Edit) return;
    w3Edit.tool = button.dataset.editorTool;
    document.querySelectorAll("[data-editor-tool]").forEach((item) => {
      item.setAttribute("aria-pressed", String(item === button));
    });
  });
});
w3BrushSize.addEventListener("input", () => { w3BrushValue.textContent = w3BrushSize.value; });
document.querySelector("#w3ZoomOut").addEventListener("click", () => setW3Zoom((w3Edit?.zoom || 1) - 0.25));
document.querySelector("#w3ZoomIn").addEventListener("click", () => setW3Zoom((w3Edit?.zoom || 1) + 0.25));

function changeW3Frame(delta) {
  if (!w3Edit) return;
  commitW3Frame();
  w3Edit.frame = (w3Edit.frame + delta + w3Edit.frameCount) % w3Edit.frameCount;
  renderW3Frame();
}
document.querySelector("#w3PrevFrame").addEventListener("click", () => changeW3Frame(-1));
document.querySelector("#w3NextFrame").addEventListener("click", () => changeW3Frame(1));
document.querySelector("#w3AutoPlay").addEventListener("click", (event) => {
  if (!w3Edit) return;
  if (w3Edit.playing) {
    stopW3Playback();
    return;
  }
  commitW3Frame();
  w3Edit.playing = true;
  event.currentTarget.textContent = "⏸ Остановить";
  event.currentTarget.setAttribute("aria-pressed", "true");
  w3Edit.playTimer = window.setInterval(() => {
    w3Edit.frame = (w3Edit.frame + 1) % w3Edit.frameCount;
    renderW3Frame();
    document.querySelector('.w3-timeline-frame[aria-current]')?.scrollIntoView({
      behavior: "smooth", block: "nearest", inline: "center",
    });
  }, 1000 / w3Edit.fps);
});

function requestW3FrameUpload(mode) {
  if (!w3Edit) return;
  w3Edit.uploadMode = mode;
  const input = document.querySelector("#w3FrameUpload");
  input.value = "";
  input.click();
}

document.querySelector("#w3ReplaceFrame").addEventListener("click", () => requestW3FrameUpload("replace"));
document.querySelector("#w3InsertBefore").addEventListener("click", () => requestW3FrameUpload("before"));
document.querySelector("#w3InsertAfter").addEventListener("click", () => requestW3FrameUpload("after"));
document.querySelector("#w3FrameUpload").addEventListener("change", async (event) => {
  const file = event.target.files?.[0];
  if (!w3Edit || !file) return;
  const bitmap = await createImageBitmap(file);
  commitW3Frame();
  const frame = createW3Frame(bitmap);
  bitmap.close();
  const frames = [...w3Edit.frames];
  let selected = w3Edit.frame;
  if (w3Edit.uploadMode === "replace") {
    frames[selected] = frame;
  } else {
    selected += w3Edit.uploadMode === "after" ? 1 : 0;
    frames.splice(selected, 0, frame);
  }
  setW3Frames(frames, selected);
  w3EditorStatus.textContent = w3Edit.uploadMode === "replace" ? "Кадр заменён" : "Кадр вставлен";
});

document.querySelector("#w3DuplicateFrame").addEventListener("click", () => {
  if (!w3Edit) return;
  commitW3Frame();
  const frames = [...w3Edit.frames];
  frames.splice(w3Edit.frame + 1, 0, createW3Frame(w3Edit.frames[w3Edit.frame]));
  setW3Frames(frames, w3Edit.frame + 1);
  w3EditorStatus.textContent = "Кадр продублирован";
});

document.querySelector("#w3Interpolate").addEventListener("click", async (event) => {
  if (!w3Edit || w3Edit.frameCount < 2) return;
  const button = event.currentTarget;
  button.disabled = true;
  stopW3Playback();
  w3EditorStatus.textContent = "WAN генерирует кадр между соседями…";
  try {
    commitW3Frame();
    const rightIndex = (w3Edit.frame + 1) % w3Edit.frameCount;
    const toBlob = (canvas) => new Promise((resolve, reject) => canvas.toBlob(
      (blob) => blob ? resolve(blob) : reject(new Error("Не удалось подготовить кадр")),
      "image/png",
    ));
    const data = new FormData();
    data.append("left", await toBlob(w3Edit.frames[w3Edit.frame]), "left.png");
    data.append("right", await toBlob(w3Edit.frames[rightIndex]), "right.png");
    const componentId = new URL(window.location.href).searchParams.get("component");
    const response = await fetch(
      `/api/components/${encodeURIComponent(componentId)}/interpolate-frame`,
      { method: "POST", body: data },
    );
    if (!response.ok) {
      const payload = (response.headers.get("content-type") || "").includes("application/json")
        ? await response.json() : null;
      throw new Error(payload?.error || `Ошибка генерации: ${response.status}`);
    }
    const bitmap = await createImageBitmap(await response.blob());
    const middle = createW3Frame(bitmap);
    bitmap.close();
    const frames = [...w3Edit.frames];
    frames.splice(w3Edit.frame + 1, 0, middle);
    setW3Frames(frames, w3Edit.frame + 1);
    w3EditorStatus.textContent = "WAN сгенерировал промежуточный кадр по двум соседям";
  } catch (error) {
    w3EditorStatus.textContent = error.message;
  } finally {
    button.disabled = false;
  }
});

document.querySelector("#w3DeleteFrame").addEventListener("click", () => {
  if (!w3Edit || w3Edit.frameCount <= 1) {
    w3EditorStatus.textContent = "Нельзя удалить единственный кадр";
    return;
  }
  const frames = w3Edit.frames.filter((_, index) => index !== w3Edit.frame);
  setW3Frames(frames, Math.min(w3Edit.frame, frames.length - 1));
  w3EditorStatus.textContent = "Кадр удалён";
});
w3Undo.addEventListener("click", () => {
  if (!w3Edit?.undo.length) return;
  const entry = w3Edit.undo.pop();
  commitW3Frame();
  w3Edit.frame = entry.frame;
  w3EditorCanvas.getContext("2d").putImageData(entry.pixels, 0, 0);
  commitW3Frame();
  renderW3Frame();
});

function w3PointerPosition(event) {
  const rect = w3EditorCanvas.getBoundingClientRect();
  return {
    x: Math.max(0, Math.min(511, Math.floor((event.clientX - rect.left) * 512 / rect.width))),
    y: Math.max(0, Math.min(511, Math.floor((event.clientY - rect.top) * 512 / rect.height))),
  };
}

function eraseW3At(event) {
  if (!w3Edit || w3Edit.tool !== "eraser") return;
  const { x, y } = w3PointerPosition(event);
  const ctx = w3EditorCanvas.getContext("2d");
  ctx.save();
  ctx.globalCompositeOperation = "destination-out";
  ctx.beginPath();
  ctx.arc(x, y, Number(w3BrushSize.value) / 2, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
  commitW3Frame();
}
w3EditorCanvas.addEventListener("pointerdown", (event) => {
  if (!w3Edit) return;
  const { x, y } = w3PointerPosition(event);
  if (w3Edit.tool === "fill") {
    removeConnectedArea(x, y);
    return;
  }
  pushW3Undo();
  w3Edit.drawing = true;
  w3EditorCanvas.setPointerCapture(event.pointerId);
  eraseW3At(event);
});
w3EditorCanvas.addEventListener("pointermove", (event) => {
  if (w3Edit?.drawing) eraseW3At(event);
});
w3EditorCanvas.addEventListener("pointerup", () => { if (w3Edit) w3Edit.drawing = false; });
w3EditorCanvas.addEventListener("pointercancel", () => { if (w3Edit) w3Edit.drawing = false; });

document.querySelector("#w3EditorSave").addEventListener("click", async () => {
  if (!w3Edit) return;
  const button = document.querySelector("#w3EditorSave");
  button.disabled = true;
  w3EditorStatus.textContent = "Сохраняем…";
  try {
    commitW3Frame();
    const sheet = document.createElement("canvas");
    sheet.width = w3Edit.frameCount * 512;
    sheet.height = 512;
    const sheetCtx = sheet.getContext("2d");
    w3Edit.frames.forEach((frame, index) => sheetCtx.drawImage(frame, index * 512, 0));
    const blob = await new Promise((resolve, reject) => sheet.toBlob(
      (value) => value ? resolve(value) : reject(new Error("Не удалось собрать PNG")),
      "image/png",
    ));
    const componentId = new URL(window.location.href).searchParams.get("component");
    const data = new FormData();
    data.append("action", w3Edit.action);
    data.append("frame_count", String(w3Edit.frameCount));
    data.append("spritesheet", blob, `${w3Edit.action}_w3_edited.png`);
    const result = await readJson(await fetch(`/api/components/${encodeURIComponent(componentId)}/w3-edit`, {
      method: "POST",
      body: data,
    }));
    readyManifestUrl = result.manifest_url;
    const status = await readJson(await fetch(`/api/components/${encodeURIComponent(componentId)}`, { cache: "no-store" }));
    renderPipeline(status.pipeline || []);
    w3EditorDialog.close();
  } catch (error) {
    w3EditorStatus.textContent = error.message;
  } finally {
    button.disabled = false;
  }
});

const initialManifest = new URL(window.location.href).searchParams.get("manifest");
const initialComponent = new URL(window.location.href).searchParams.get("component");
loadActionCatalog().catch((error) => setError(error.message));
if (initialManifest) {
  const manifestPath = new URL(initialManifest, window.location.href).pathname;
  const componentMatch = manifestPath.match(/^\/api\/components\/([^/]+)\/manifest$/);
  const hydrate = componentMatch
    ? fetch(`/api/components/${encodeURIComponent(componentMatch[1])}`, { cache: "no-store" })
      .then(readJson)
      .then((status) => {
        renderPipeline(status.pipeline || []);
        renderStage.textContent = status.stage || status.message || "Готово";
        renderPercent.textContent = `${Math.round(Number(status.progress) || 100)}%`;
        unlockTab("render", true);
      })
    : Promise.resolve();
  hydrate.then(() => showResult(initialManifest)).catch((error) => {
    resultStatus.textContent = error.message;
    resultStatus.hidden = false;
  });
} else if (initialComponent) {
  unlockTab("render", true);
  selectTab("render");
  waitForComponent(`/api/components/${encodeURIComponent(initialComponent)}`)
    .then((manifestUrl) => {
      readyManifestUrl = manifestUrl;
      openComponent.disabled = false;
      unlockTab("result", true);
      renderStage.textContent = "Все выбранные анимации готовы";
      renderPercent.textContent = "100%";
    })
    .catch((error) => {
      if (error.name === "AbortError") return;
      renderStage.textContent = error.message;
      renderPercent.textContent = "Ошибка";
    });
} else {
  loadCharacterLibrary();
}
