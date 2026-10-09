import { defineConfig } from "@playwright/test";

const python = process.env.SPRITE_EXTRACTOR_TEST_PYTHON ?? "python3";
const staticRoot = process.env.SPRITE_EXTRACTOR_TEST_STATIC_ROOT ?? "/tmp/sprite-extractor-cycle-review-static";
const shellQuote = (value: string) => `'${value.replace(/'/g, "'\\''")}'`;

export default defineConfig({
  testDir: "./tests",
  testMatch: "backend-integration.spec.ts",
  use: { baseURL: "http://127.0.0.1:4181/sprites" },
  webServer: {
    command: `${shellQuote(python)} web/tests/backend_server.py --port 4181 --static-root ${shellQuote(staticRoot)}`,
    cwd: "..",
    env: { PYTHONPATH: "src" },
    url: "http://127.0.0.1:4181/sprites/api/catalog",
    reuseExistingServer: false,
  },
});
