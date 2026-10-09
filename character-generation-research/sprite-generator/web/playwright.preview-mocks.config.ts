import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  testIgnore: ["**/backend-integration.spec.ts", "**/raw-previews.spec.ts"],
  timeout: 30_000,
  use: { baseURL: "http://127.0.0.1:4176", screenshot: "only-on-failure" },
  webServer: {
    command:
      "npx vite preview --host 127.0.0.1 --port 4176 --outDir /tmp/sprite-extractor-web-preview-static",
    url: "http://127.0.0.1:4176",
    reuseExistingServer: false,
  },
});
