import { expect, test } from "@playwright/test";

const catalog = {
  revision: "catalog",
  actions: [
    {
      id: "walk",
      label: "Walk",
      description: "",
      stage: "run",
      selection: { method: "cycle", frames: 4 },
      frame_count: { value: 4, editable: true },
      conceptual_loop: true,
      animated_file: true,
    },
  ],
  poses: [],
  capabilities: {
    directions: ["right", "left", "back", "front"],
    prompt_styles: ["neutral"],
    split_methods: ["blobs"],
    animation_authoring: false,
  },
};
const job = {
  id: "job_preview",
  workspace_id: "ws_preview",
  status: "generating",
  phase: "generating",
  current_stage: "run",
  completed_stages: 1,
  total_stages: 2,
  cached_stages: 0,
  resolved_seed: "42",
  created_at: "",
  started_at: "",
  finished_at: null,
  elapsed_seconds: 0,
  stop_requested: false,
  resume_allowed: false,
  message: "Generating",
  package_id: null,
  links: {
    self: "/api/jobs/job_preview",
    events: "/api/jobs/job_preview/events",
  },
  request: {
    workspace_id: "ws_preview",
    actions: ["walk"],
    frame_counts: { walk: 4 },
    style: "neutral",
    seed: { mode: "fixed", value: "42" },
    sprite_size: 256,
    generation: { width: 400, height: 512, pad_top_percent: 0 },
    split_method: "blobs",
    animation_overrides: {},
  },
};
const workspace = {
  id: "ws_preview",
  name: "Preview",
  source: {
    id: "up",
    filename: "hero.png",
    media_type: "image/png",
    width: 1,
    height: 1,
    bytes: 1,
    sha256: "x",
    thumbnail_url: "#",
  },
  created_at: "",
  storage_bytes: 1,
  jobs: [job],
};
const assets = {
  job_id: "job_preview",
  stages: [
    {
      stage_id: "prepare",
      label: "Prepare",
      reason: "dependency",
      action_id: null,
      dependency_for: ["walk"],
      assets: [
        {
          id: "pv_video",
          kind: "video",
          pose_id: null,
          filename: "prepare.mp4",
          media_type: "video/mp4",
          bytes: 10,
          sha256: "a",
          url: "/api/previews/pv_video",
        },
      ],
    },
    {
      stage_id: "run",
      label: "Run",
      reason: "selected",
      action_id: "walk",
      dependency_for: ["walk"],
      assets: [
        {
          id: "pv_pose",
          kind: "pose",
          pose_id: "standing",
          filename: "standing.png",
          media_type: "image/png",
          bytes: 10,
          sha256: "b",
          url: "/api/previews/pv_pose",
        },
      ],
    },
  ],
};

test("raw previews poll progressively and open accessible media without changing selection", async ({
  page,
}) => {
  let publishPreviews = false;
  await page.route("**/api/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith("/session"))
      return route.fulfill({
        json: {
          authenticated: true,
          operator: "local",
          csrf_token: "x",
          auth_required: false,
        },
      });
    if (path.endsWith("/catalog")) return route.fulfill({ json: catalog });
    if (path.endsWith("/jobs/job_preview/activity"))
      return route.fulfill({ json: { job, current: null, activities: [], next_cursor: 0 } });
    if (path.endsWith("/jobs/job_preview/previews")) {
      return route.fulfill({
        json: publishPreviews ? assets : { job_id: "job_preview", stages: [] },
      });
    }
    if (path.endsWith("/jobs/job_preview")) return route.fulfill({ json: job });
    if (path.endsWith("/workspaces/ws_preview"))
      return route.fulfill({ json: workspace });
    if (path.endsWith("/config"))
      return route.fulfill({
        json: { revision: "config", path: "config", fields: [] },
      });
    if (path.endsWith("/previews/pv_video"))
      return route.fulfill({ contentType: "video/mp4", body: "video" });
    if (path.endsWith("/previews/pv_pose"))
      return route.fulfill({ contentType: "image/png", body: "image" });
    return route.fulfill({ status: 404, json: { error: { message: path } } });
  });
  await page.goto("/?job=job_preview");
  await page.getByRole("button", { name: "Dismiss" }).click();
  const selected = page.getByRole("checkbox", { name: /Walk/ });
  await expect(selected).toBeChecked();
  const strip = page.getByLabel("Raw previews for walk");
  await expect(strip.getByText("Raw output pending")).toBeVisible();
  publishPreviews = true;
  await expect(
    strip.getByRole("button", {
      name: /Open Prepare video dependency for walk/,
    }),
  ).toBeVisible({ timeout: 5_000 });
  const opener = strip.getByRole("button", {
    name: /Open Prepare video dependency for walk/,
  });
  await opener.click();
  const dialog = page.getByRole("dialog", {
    name: /Prepare video dependency for walk/,
  });
  const video = dialog.locator(
    "video[aria-label='Prepare video dependency for walk']",
  );
  await expect(video).toBeVisible();
  await expect(video).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(dialog).toHaveCount(0);
  await expect(opener).toBeFocused();
  await expect(selected).toBeChecked();
  await expect(
    strip.getByRole("button", { name: /Open Run image · standing/ }),
  ).toBeVisible();
});

test("unavailable raw previews remain supplementary and do not break a saved job", async ({
  page,
}) => {
  const failedJob = { ...job, status: "failed", message: "Generation failed" };
  await page.route("**/api/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith("/session"))
      return route.fulfill({
        json: { authenticated: true, operator: "local", auth_required: false },
      });
    if (path.endsWith("/catalog")) return route.fulfill({ json: catalog });
    if (path.endsWith("/jobs/job_preview/activity"))
      return route.fulfill({
        json: {
          job: failedJob,
          current: {
            sequence: 1,
            timestamp: "",
            state: "failed",
            operation: "generation",
            stage_id: null,
            prompt_id: null,
            message: "Generation failed",
            error: { code: "failed", message: "Generation failed", retryable: false },
          },
          activities: [],
          next_cursor: 1,
        },
      });
    if (path.endsWith("/jobs/job_preview/previews"))
      return route.fulfill({
        status: 503,
        json: { error: { message: "temporarily unavailable" } },
      });
    if (path.endsWith("/jobs/job_preview"))
      return route.fulfill({ json: failedJob });
    if (path.endsWith("/workspaces/ws_preview"))
      return route.fulfill({ json: workspace });
    if (path.endsWith("/config"))
      return route.fulfill({
        json: { revision: "config", path: "config", fields: [] },
      });
    return route.fulfill({ status: 404, json: { error: { message: path } } });
  });
  await page.goto("/?job=job_preview");
  await expect(page.getByRole("checkbox", { name: /Walk/ })).toBeChecked();
  await expect(
    page.getByLabel("Raw previews for walk").getByText("Raw output pending"),
  ).toBeVisible();
  await expect(
    page.locator("main").getByRole("alert").filter({ hasText: "Generation failed" }),
  ).toBeVisible();
});

test("stage ownership puts a shared dependency spinner and preview on one immutable consumer", async ({
  page,
}) => {
  const ownerCatalog = {
    ...catalog,
    actions: [
      { ...catalog.actions[0], id: "idle", label: "Idle", stage: "idle" },
      { ...catalog.actions[0], id: "walk", label: "Walk", stage: "walk" },
    ],
  };
  let mode: "generating" | "stop_requested" | "stopped" = "generating";
  let publishAsset = false;
  const ownerJob = {
    ...job,
    request: { ...job.request, actions: ["walk", "idle"] },
    current_stage: "stop",
  };
  const currentJob = () =>
    mode === "stopped"
      ? { ...ownerJob, status: "stopped", phase: "stopped", current_stage: null }
      : { ...ownerJob, status: mode, phase: mode, current_stage: "stop" };
  const ownerPreviews = () => ({
    job_id: ownerJob.id,
    stage_owners: { stop: "idle", idle: "idle", walk: "walk" },
    stages: publishAsset
      ? [
          {
            stage_id: "stop",
            label: "Stop",
            reason: "dependency",
            action_id: null,
            owner_action_id: "idle",
            dependency_for: ["idle", "walk"],
            assets: [
              {
                id: "pv_stop",
                kind: "video",
                pose_id: null,
                filename: "stop.mp4",
                media_type: "video/mp4",
                bytes: 10,
                sha256: "stop",
                url: "/api/previews/pv_stop",
              },
            ],
          },
        ]
      : [],
  });
  await page.route("**/api/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith("/session"))
      return route.fulfill({
        json: { authenticated: true, operator: "local", auth_required: false },
      });
    if (path.endsWith("/catalog")) return route.fulfill({ json: ownerCatalog });
    if (path.endsWith("/jobs/job_preview/activity"))
      return route.fulfill({
        json: { job: currentJob(), current: null, activities: [], next_cursor: 0 },
      });
    if (path.endsWith("/jobs/job_preview/previews"))
      return route.fulfill({ json: ownerPreviews() });
    if (path.endsWith("/jobs/job_preview"))
      return route.fulfill({ json: currentJob() });
    if (path.endsWith("/workspaces/ws_preview"))
      return route.fulfill({ json: { ...workspace, jobs: [ownerJob] } });
    if (path.endsWith("/config"))
      return route.fulfill({ json: { revision: "config", path: "config", fields: [] } });
    if (path.endsWith("/previews/pv_stop"))
      return route.fulfill({ contentType: "video/mp4", body: "video" });
    return route.fulfill({ status: 404, json: { error: { message: path } } });
  });
  await page.goto("/?job=job_preview");
  await page.getByRole("button", { name: "Dismiss" }).click();
  const idle = page.getByLabel("Raw previews for idle");
  const walk = page.getByLabel("Raw previews for walk");
  await expect(page.locator(".editor-busy-spinner").filter({ hasText: "Generating stop for Idle" })).toBeVisible();
  await expect(page.locator(".editor-busy-spinner").filter({ hasText: /Generating .*Walk/ })).toHaveCount(0);
  await expect(idle.getByText("Raw output pending")).toBeVisible();
  await expect(walk.getByText("Raw output pending")).toBeVisible();
  publishAsset = true;
  const opener = idle.getByRole("button", { name: /Open Stop video dependency for idle/ });
  await expect(opener).toBeVisible({ timeout: 5_000 });
  await expect(walk.getByRole("button", { name: /Open Stop video/ })).toHaveCount(0);
  await opener.click();
  await expect(page.getByRole("dialog", { name: /Stop video dependency for idle/ })).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(opener).toBeFocused();
  mode = "stop_requested";
  await page.reload();
  await expect(page.locator(".editor-busy-spinner").filter({ hasText: "Generating stop for Idle" })).toBeVisible();
  mode = "stopped";
  await page.reload();
  await expect(page.locator(".editor-busy-spinner")).toHaveCount(0);
});
