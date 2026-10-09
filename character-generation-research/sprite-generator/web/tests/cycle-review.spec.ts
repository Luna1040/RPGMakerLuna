import { expect, test } from "@playwright/test";

const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL8WAAAAABJRU5ErkJggg==", "base64");
const catalog = { revision: "catalog", actions: [
  { id: "run", label: "Run", description: "", stage: "run", selection: { method: "cycle", frames: 2 }, frame_count: { value: 2, editable: true }, conceptual_loop: true, animated_file: true },
  { id: "walk", label: "Walk", description: "", stage: "walk", selection: { method: "cycle", frames: 2 }, frame_count: { value: 2, editable: true }, conceptual_loop: true, animated_file: true },
], poses: [], capabilities: { directions: ["right", "left", "back", "front"], prompt_styles: ["neutral"], split_methods: ["blobs"], animation_authoring: false } };
const parent = { id: "job_cycle", workspace_id: "ws_cycle", status: "ready", phase: "ready", current_stage: null, completed_stages: 2, total_stages: 2, cached_stages: 0, resolved_seed: "42", created_at: "", started_at: "", finished_at: "", elapsed_seconds: 0, stop_requested: false, resume_allowed: false, message: "Ready", package_id: "pkg_cycle", kind: "render", parent_job_id: null, base_package_id: null, links: { self: "/api/jobs/job_cycle", events: "/api/jobs/job_cycle/events" }, request: { workspace_id: "ws_cycle", actions: ["run", "walk"], frame_counts: { run: 2, walk: 2 }, style: "neutral", seed: { mode: "fixed", value: "42" }, sprite_size: 16, generation: { width: 400, height: 512, pad_top_percent: 0 }, split_method: "blobs", animation_overrides: {} } };
const candidate = (index: number) => ({ id: `cycle_${index}`, start_time_seconds: index, end_time_seconds: index + 0.8, period_seconds: 0.8, frames: [0, 1].map((frame) => ({ id: `asset_${index}_${frame}`, frame_id: `f${index}_${frame}`, pts: index * 100 + frame, time_seconds: index + frame * 0.4, url: `/api/cycle-assets/asset_${index}_${frame}` })), frame_durations_ms: [25, 50], system_selected: index === 3 });
const review = { job_id: parent.id, can_revise: true, can_analyze: true, groups: [
  { action: "run", label: "Run", stage_id: "run", status: "ready", message: null, analysis_id: "analysis_run", system_candidate_id: "cycle_3", selected_candidate_id: "cycle_3", selection_origin: "automatic", frame_count: 2, candidates: [1,2,3,4,5,6].map(candidate) },
  { action: "walk", label: "Walk", stage_id: "walk", status: "ready", message: null, analysis_id: "analysis_walk", system_candidate_id: "cycle_1", selected_candidate_id: "cycle_1", selection_origin: "automatic", frame_count: 2, candidates: [candidate(1)] },
] };
const workspace = { id: "ws_cycle", name: "Cycle", source: { id: "up", filename: "hero.png", media_type: "image/png", width: 1, height: 1, bytes: 1, sha256: "x", thumbnail_url: "#" }, created_at: "", storage_bytes: 1, jobs: [parent] };
const pkg = { id: "pkg_cycle", job_id: parent.id, created_at: "", sheet: { artifact_id: "sheet", filename: "sheet.png", media_type: "image/png", bytes: 1, url: "/api/artifacts/sheet" }, metadata: { artifact_id: "meta", filename: "sheet.json", media_type: "application/json", bytes: 1, url: "#" }, manifest: { artifact_id: "manifest", filename: "manifest.json", media_type: "application/json", bytes: 1, url: "#" }, animations: [{ action: "run", direction: "right", artifact_id: "run", filename: "run.webp", media_type: "image/webp", bytes: 1, url: "#" }], still_actions: [], download_url: "#", action_downloads: { run: "#" }, preview: { layout: { rows: 4, columns: 2, cell_size: 16, directions: ["right", "left", "back", "front"], animation_ranges: { run: [0,2], walk: [0,2] } }, frame_durations_ms: { "run:right": [25,50] } } };

test("cycle chooser keeps a staged choice and submits one revision", async ({ page }) => {
  let revisions = 0;
  await page.route("**/api/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith("/session")) return route.fulfill({ json: { authenticated: true, operator: "local", auth_required: false } });
    if (path.endsWith("/catalog")) return route.fulfill({ json: catalog });
    if (path.endsWith("/config")) return route.fulfill({ json: { revision: "x", path: "x", fields: [] } });
    if (path.endsWith("/connection-check")) return route.fulfill({ json: { ok: true, message: "ready", url: "mock", models: [] } });
    if (path.endsWith("/jobs/job_cycle/cycles")) return route.fulfill({ json: review });
    if (path.endsWith("/jobs/job_cycle/activity")) return route.fulfill({ json: { job: parent, current: null, activities: [], next_cursor: 0 } });
    if (path.endsWith("/jobs/job_cycle/previews")) return route.fulfill({ json: { job_id: parent.id, stage_owners: {}, stages: [] } });
    if (path.endsWith("/jobs/job_cycle")) return route.fulfill({ json: parent });
    if (path.endsWith("/workspaces/ws_cycle")) return route.fulfill({ json: workspace });
    if (path.endsWith("/packages/pkg_cycle")) return route.fulfill({ json: pkg });
    if (path.endsWith("/artifacts/sheet") || path.includes("/cycle-assets/")) return route.fulfill({ contentType: "image/png", body: png });
    if (path.endsWith("/cycle-revisions")) { revisions++; return route.fulfill({ status: 202, json: { ...parent, id: "job_revision", status: "queued", phase: "queued", kind: "cycle_revision", parent_job_id: parent.id, base_package_id: pkg.id, package_id: null } }); }
    return route.fulfill({ status: 404, json: { error: { message: path } } });
  });
  await page.goto("/?job=job_cycle");
  await expect(page.getByRole("heading", { name: "Your sprite package" })).toBeVisible();
  await page.getByRole("button", { name: "Review cycles (6)" }).first().click();
  const dialog = page.getByRole("dialog", { name: "Review cycles (7)" });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByText("System pick · Middle complete cycle")).toBeVisible();
  await expect(dialog.getByRole("button", { name: "Pause all" })).toBeVisible();
  await dialog.getByRole("button", { name: "Pause all" }).click();
  await expect(dialog.getByRole("button", { name: "Play all" })).toBeVisible();
  const frame = dialog.getByRole("group", { name: "Cycle preview playback" }).getByText(/Frame \d+ \/ 2/);
  const beforeStep = await frame.innerText();
  await dialog.getByRole("button", { name: "Next frame" }).click();
  await expect(frame).not.toHaveText(beforeStep);
  await dialog.getByRole("button", { name: "Next candidates" }).click();
  await expect(dialog.getByRole("radio", { name: "Cycle 5" })).toBeVisible();
  await dialog.getByRole("radio", { name: "Cycle 5" }).check();
  const enlarge = dialog.getByRole("button", { name: "Enlarge" }).first();
  await enlarge.click();
  await expect(page.getByRole("dialog", { name: /Run cycle 5 four-view frame/ })).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(dialog).toBeVisible();
  await expect(enlarge).toBeFocused();
  await expect(dialog.getByRole("radio", { name: "Cycle 5" })).toBeChecked();
  await dialog.getByRole("button", { name: "Update sprite sheet" }).click();
  await expect(page.getByRole("heading", { name: "Your sprite package" })).toBeVisible();
  expect(revisions).toBe(1);
});
