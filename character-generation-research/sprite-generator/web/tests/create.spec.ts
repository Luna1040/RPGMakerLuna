import { expect, test } from "@playwright/test";
const catalog = {
  revision: "test",
  actions: [
    {
      id: "idle",
      label: "Idle",
      description: "Rest pose",
      stage: "idle",
      selection: { method: "uniform", frames: 4, include_last: false },
      frame_count: { value: 4, editable: true, minimum: 2 },
      conceptual_loop: true,
      animated_file: true,
    },
    {
      id: "walk",
      label: "Walk",
      description: "Moves",
      stage: "walk",
      selection: { method: "uniform", frames: 4, include_last: false },
      frame_count: { value: 4, editable: true, minimum: 2 },
      conceptual_loop: true,
      animated_file: true,
    },
    {
      id: "crouch",
      label: "Crouch",
      description: "Still pose",
      stage: "crouch",
      selection: { method: "single", frames: 1, include_last: true },
      frame_count: { value: 1, editable: false },
      conceptual_loop: false,
      animated_file: false,
    },
  ],
  poses: [],
  capabilities: {
    directions: ["right", "left", "back", "front"],
    prompt_styles: ["neutral", "feminine"],
    split_methods: ["blobs", "quarters"],
    animation_authoring: false,
  },
};
test.beforeEach(async ({ page }) => {
  await page.route("**/api/session", (route) =>
    route.fulfill({
      json: { authenticated: true, operator: "local", csrf_token: "csrf" },
    }),
  );
  await page.route("**/api/catalog", (route) =>
    route.fulfill({ json: catalog }),
  );
  await page.route("**/api/config", (route) =>
    route.fulfill({ json: { revision: "x", path: "config.yaml", fields: [] } }),
  );
  await page.route("**/api/connection-check", (route) =>
    route.fulfill({
      json: {
        ok: true,
        message: "Mocked ComfyUI ready",
        url: "mocked",
        models: [],
      },
    }),
  );
});
test("keyboard selection and generation retain the single-page setup", async ({
  page,
}) => {
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: "Create sprites" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Choose image" }).press("Enter");
  await page.getByRole("button", { name: "Clear" }).click();
  await expect(
    page.getByRole("button", { name: "Generate sprites" }),
  ).toBeDisabled();
  await page.getByRole("button", { name: "Select all" }).click();
  await expect(page.getByText("3 animations")).toBeVisible();
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(
    page.getByRole("heading", { name: "Render settings" }),
  ).toBeVisible();
});

test("generation works on insecure LAN pages without crypto.randomUUID", async ({
  page,
}) => {
  const png = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL8WAAAAABJRU5ErkJggg==",
    "base64",
  );
  let jobs = 0;
  await page.addInitScript(() =>
    Object.defineProperty(crypto, "randomUUID", {
      value: undefined,
      configurable: true,
    }),
  );
  await page.route("**/api/uploads", (route) =>
    route.fulfill({
      status: 201,
      json: {
        id: "up_lan",
        filename: "samus.jpg",
        media_type: "image/jpeg",
        width: 1,
        height: 1,
        bytes: 1,
        sha256: "x",
        thumbnail_url: "#",
      },
    }),
  );
  await page.route("**/api/workspaces", (route) =>
    route.fulfill({
      status: 201,
      json: {
        id: "ws_lan",
        name: "Samus",
        source: {
          id: "up_lan",
          filename: "samus.jpg",
          media_type: "image/jpeg",
          width: 1,
          height: 1,
          bytes: 1,
          sha256: "x",
          thumbnail_url: "#",
        },
        created_at: "",
        storage_bytes: 1,
      },
    }),
  );
  const request = {
    workspace_id: "ws_lan",
    actions: ["walk"],
    frame_counts: { walk: 4 },
    style: "neutral",
    seed: { mode: "random" },
    sprite_size: 256,
    generation: { width: 400, height: 512, pad_top_percent: 0 },
    split_method: "blobs",
    animation_overrides: {},
  };
  const job = {
    id: "job_lan",
    workspace_id: "ws_lan",
    status: "queued",
    phase: "queued",
    current_stage: null,
    completed_stages: 0,
    total_stages: 1,
    cached_stages: 0,
    resolved_seed: "7",
    created_at: "",
    started_at: null,
    finished_at: null,
    elapsed_seconds: 0,
    stop_requested: false,
    resume_allowed: false,
    message: "Queued",
    package_id: null,
    links: { self: "/api/jobs/job_lan", events: "/api/jobs/job_lan/events" },
    request,
  };
  await page.route("**/api/plans", (route) =>
    route.fulfill({
      json: {
        request,
        resolved_seed: "7",
        summary: { animation_count: 1, frames_per_direction: 4, directions: 4 },
        stages: [],
        definition_snapshot: "x",
        config_snapshot: "x",
      },
    }),
  );
  await page.route("**/api/jobs", (route) => {
    jobs++;
    return route.fulfill({ status: 202, json: job });
  });
  await page.route("**/api/jobs/job_lan", (route) => route.fulfill({ json: job }));
  await page.route("**/api/jobs/job_lan/activity**", (route) =>
    route.fulfill({ json: { job, current: null, activities: [], next_cursor: 0 } }),
  );
  await page.route("**/api/jobs/job_lan/previews", (route) =>
    route.fulfill({ json: { job_id: job.id, stages: [] } }),
  );
  await page.goto("/");
  await page
    .locator("input[type=file]")
    .setInputFiles({ name: "samus.jpg", mimeType: "image/jpeg", buffer: png });
  await page.getByRole("button", { name: "Generate sprites" }).click();
  await expect(page.getByRole("dialog", { name: "Generation activity" })).toBeVisible();
  expect(jobs).toBe(1);
});

test("ready package uses actual sheet layout for direction, still and playback controls", async ({
  page,
}) => {
  const png = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL8WAAAAABJRU5ErkJggg==",
    "base64",
  );
  const job = {
    id: "job_1",
    workspace_id: "ws_1",
    status: "ready",
    phase: "ready",
    current_stage: null,
    completed_stages: 1,
    total_stages: 1,
    cached_stages: 0,
    resolved_seed: "9",
    created_at: "",
    started_at: "",
    finished_at: "",
    elapsed_seconds: 0,
    stop_requested: false,
    resume_allowed: false,
    message: "Ready",
    package_id: "pkg_1",
    links: { self: "/api/jobs/job_1", events: "/api/jobs/job_1/events" },
    request: {
      workspace_id: "ws_1",
      actions: ["walk", "run", "crouch"],
      frame_counts: { walk: 2, run: 2, crouch: 1 },
      style: "neutral",
      seed: { mode: "fixed", value: "9" },
      sprite_size: 16,
      generation: { width: 400, height: 512, pad_top_percent: 0 },
      split_method: "blobs",
      animation_overrides: {},
    },
  };
  const pkg = {
    id: "pkg_1",
    job_id: "job_1",
    created_at: "",
    sheet: {
      artifact_id: "sheet",
      filename: "sheet.png",
      media_type: "image/png",
      bytes: 1,
      url: "/api/artifacts/sheet",
    },
    metadata: {
      artifact_id: "meta",
      filename: "sheet.json",
      media_type: "application/json",
      bytes: 1,
      url: "#",
    },
    manifest: {
      artifact_id: "manifest",
      filename: "manifest.json",
      media_type: "application/json",
      bytes: 1,
      url: "#",
    },
    animations: [
      {
        action: "run",
        direction: "right",
        artifact_id: "rr",
        filename: "run-right.webp",
        media_type: "image/webp",
        bytes: 1,
        url: "#",
      },
      {
        action: "run",
        direction: "left",
        artifact_id: "rl",
        filename: "run-left.webp",
        media_type: "image/webp",
        bytes: 1,
        url: "#",
      },
      {
        action: "walk",
        direction: "right",
        artifact_id: "wr",
        filename: "walk-right.webp",
        media_type: "image/webp",
        bytes: 1,
        url: "#",
      },
    ],
    still_actions: ["crouch"],
    download_url: "#",
    action_downloads: { walk: "#" },
    preview: {
      layout: {
        rows: 4,
        columns: 5,
        cell_size: 16,
        directions: ["right", "left", "back", "front"],
        animation_ranges: { walk: [0, 2], run: [2, 4], crouch: [4, 5] },
      },
      frame_durations_ms: {
        "walk:right": [25, 50],
        "walk:left": [25, 50],
        "run:right": [25, 50],
        "run:left": [25, 50],
      },
    },
  };
  await page.unrouteAll();
  await page.route("**/api/**", async (route) => {
    const u = new URL(route.request().url()),
      p = u.pathname,
      m = route.request().method();
    if (p.endsWith("/session"))
      return route.fulfill({
        json: { authenticated: true, operator: "local", csrf_token: "csrf" },
      });
    if (p.endsWith("/catalog")) return route.fulfill({ json: catalog });
    if (p.endsWith("/connection-check"))
      return route.fulfill({
        json: { ok: true, message: "ready", url: "mock", models: [] },
      });
    if (p.endsWith("/uploads"))
      return route.fulfill({
        status: 201,
        json: {
          id: "up_1",
          filename: "hero.png",
          media_type: "image/png",
          width: 1,
          height: 1,
          bytes: 1,
          sha256: "x",
          thumbnail_url: "/api/artifacts/sheet",
        },
      });
    if (p.endsWith("/workspaces"))
      return route.fulfill({
        status: 201,
        json: {
          id: "ws_1",
          name: "Hero",
          source: {
            id: "up_1",
            filename: "hero.png",
            media_type: "image/png",
            width: 1,
            height: 1,
            bytes: 1,
            sha256: "x",
            thumbnail_url: "/api/artifacts/sheet",
          },
          created_at: "",
          storage_bytes: 1,
        },
      });
    if (p.endsWith("/plans"))
      return route.fulfill({
        json: {
          request: job.request,
          resolved_seed: null,
          summary: {
            animation_count: 2,
            frames_per_direction: 3,
            directions: 4,
          },
          stages: [],
          definition_snapshot: "x",
          config_snapshot: "x",
        },
      });
    if (p.endsWith("/jobs") && m === "POST")
      return route.fulfill({ status: 202, json: job });
    if (p.endsWith("/jobs/job_1/activity"))
      return route.fulfill({ json: { job, current: null, activities: [], next_cursor: 0 } });
    if (p.endsWith("/jobs/job_1/previews"))
      return route.fulfill({ json: { job_id: job.id, stages: [] } });
    if (p.endsWith("/packages/pkg_1")) return route.fulfill({ json: pkg });
    if (p.endsWith("/artifacts/sheet"))
      return route.fulfill({ contentType: "image/png", body: png });
    return route.fulfill({
      status: 404,
      json: { error: { message: `unexpected ${p}` } },
    });
  });
  await page.goto("/");
  await page
    .locator("input[type=file]")
    .setInputFiles({ name: "hero.png", mimeType: "image/png", buffer: png });
  await page.getByRole("button", { name: "Generate sprites" }).click();
  await expect(
    page.getByRole("heading", { name: "Your sprite package" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Dismiss" }).click();
  await page.getByRole("button", { name: "100%" }).click();
  await expect(page.getByAltText("Four-direction sprite sheet")).toHaveCSS(
    "width",
    "80px",
  );
  await page.getByLabel("Direction").selectOption("left");
  await expect(page.getByLabel("left frame 1")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Pause animation" }),
  ).toBeVisible();
  const frame = page.getByText(/^Frame \d+ \/ 2$/);
  const firstFrame = await frame.innerText();
  await expect(frame).not.toHaveText(firstFrame, { timeout: 1_000 });
  await page.getByRole("button", { name: "Pause animation" }).click();
  const pausedFrame = await frame.innerText();
  await page.waitForTimeout(125);
  await expect(frame).toHaveText(pausedFrame);
  await page.getByLabel("Direction").selectOption("right");
  await expect(page.getByRole("button", { name: "Pause animation" })).toBeVisible();
  await page.getByLabel("Action").selectOption("run");
  await expect(page.getByRole("button", { name: "Pause animation" })).toBeVisible();
  await page.getByLabel("Action").selectOption("crouch");
  await expect(page.getByText("Still pose · no animated file")).toBeVisible();
  await expect(
    page.getByRole("button", { name: /Play animation|Pause animation/ }),
  ).toBeDisabled();
});
