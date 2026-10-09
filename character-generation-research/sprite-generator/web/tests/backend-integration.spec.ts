import { expect, test } from "@playwright/test";

test("compiled backend UI uses the prefixed real API without inference", async ({
  page,
}) => {
  const png = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP8z8Dwn4GBgYGJAQoAHxcCAk+Uzr4AAAAASUVORK5CYII=",
    "base64",
  );
  let createJobPosts = 0;
  page.on("request", (request) => {
    if (
      request.method() === "POST" &&
      new URL(request.url()).pathname === "/sprites/api/jobs"
    )
      createJobPosts += 1;
  });

  await page.goto("/sprites/");
  await expect(page.getByRole("checkbox")).toHaveCount(6);
  await expect(page.getByText("Local network access")).toBeVisible();
  await expect(page.getByRole("button", { name: "Sign out" })).toHaveCount(0);
  await page
    .locator("input[type=file]")
    .setInputFiles({ name: "hero.png", mimeType: "image/png", buffer: png });
  await expect(page.getByText("hero.png")).toBeVisible();
  await page
    .getByLabel("Main navigation")
    .getByRole("button", { name: "Settings" })
    .click();
  await expect(
    page.getByRole("heading", { name: "Saved server defaults" }),
  ).toBeVisible();
  await page
    .getByLabel("Main navigation")
    .getByRole("button", { name: "Create sprites" })
    .click();
  await page.getByRole("button", { name: "Generate sprites" }).click();
  await expect(page.getByRole("heading", { name: "Queued" })).toBeVisible();
  await expect(page.getByRole("dialog", { name: "Generation activity" })).toBeVisible();
  await page.getByRole("button", { name: "Dismiss" }).click();
  await page.getByRole("link", { name: "Saved render" }).click();
  await page.reload();
  await expect(page.getByRole("heading", { name: "Queued" })).toBeVisible();
  expect(createJobPosts).toBe(1);
  expect(page.url()).toContain("/sprites");
});

test("real backend cycle review queues one pinned child and retains its parent", async ({ page, request }) => {
  const diagnostics: string[] = [];
  page.on("console", (message) => diagnostics.push(`console ${message.type()}: ${message.text()}`));
  page.on("pageerror", (error) => diagnostics.push(`pageerror: ${error.message}`));
  page.on("response", async (response) => {
    if (response.url().includes("/api/jobs/") || response.url().includes("/api/workspaces/"))
      diagnostics.push(`${response.status()} ${new URL(response.url()).pathname} ${await response.text()}`);
  });
  const jobs = await request.get("/sprites/api/jobs?limit=50");
  const parent = (await jobs.json()).jobs.find((job: { status: string; kind: string }) => job.status === "ready" && job.kind === "render");
  expect(parent).toBeTruthy();
  await page.goto(`/sprites/?job=${parent.id}`);
  const review = page.getByRole("button", { name: /Review cycles/ });
  try {
    await review.click({ timeout: 5_000 });
  } catch (error) {
    diagnostics.push(`body: ${await page.locator("body").innerText()}`);
    throw new Error(`${error}\n${diagnostics.join("\n")}`);
  }
  await expect(page.getByRole("dialog", { name: /Review cycles/ })).toContainText("System pick");
  await page.getByRole("radio", { name: "Cycle 2" }).check();
  await page.getByRole("button", { name: "Update sprite sheet" }).click();
  await expect(page.getByRole("heading", { name: "Queued" })).toBeVisible();
  const after = await request.get("/sprites/api/jobs?limit=50");
  const child = (await after.json()).jobs.find((job: { parent_job_id?: string; kind: string }) => job.parent_job_id === parent.id && job.kind === "cycle_revision");
  expect(child).toBeTruthy();
  expect((await request.get(`/sprites/api/jobs/${parent.id}`)).status()).toBe(200);
});
