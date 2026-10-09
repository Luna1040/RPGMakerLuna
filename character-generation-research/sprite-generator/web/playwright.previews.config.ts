import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  testMatch: "raw-previews.spec.ts",
  timeout: 30_000,
  use: { baseURL: "http://127.0.0.1:4175" },
  webServer: {
    command:
      "npx vite preview --host 127.0.0.1 --port 4175 --outDir /tmp/sprite-extractor-web-preview-static",
    url: "http://127.0.0.1:4175",
    reuseExistingServer: false,
  },
});
