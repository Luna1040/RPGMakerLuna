import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./tests",
  testIgnore: "**/backend-integration.spec.ts",
  timeout: 30_000,
  use: { baseURL: "http://127.0.0.1:4173", screenshot: "only-on-failure" },
  webServer: {
    command: "npm run build -- --outDir /tmp/sprite-extractor-playwright-static && npm run preview -- --host 127.0.0.1 --port 4173 --outDir /tmp/sprite-extractor-playwright-static",
    url: "http://127.0.0.1:4173",
    reuseExistingServer: false,
  },
});
