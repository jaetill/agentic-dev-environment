import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "node:path";

// Vitest configuration per ADR-0004 — tiered coverage thresholds.
// Run: pnpm test (CI mode), pnpm test:watch (dev), pnpm test:coverage

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  test: {
    globals: true,
    environment: "happy-dom",
    setupFiles: ["./tests/setup.ts"],
    include: ["tests/unit/**/*.{test,spec}.{ts,tsx}", "tests/integration/**/*.{test,spec}.{ts,tsx}"],
    exclude: ["node_modules", ".next", "tests/e2e/**"],
    coverage: {
      provider: "v8",
      reporter: ["text", "html", "json", "lcov"],
      include: ["src/**/*.{ts,tsx}"],
      exclude: [
        "src/**/*.d.ts",
        "src/**/*.stories.{ts,tsx}",
        "src/**/index.{ts,tsx}", // re-export-only barrels
        "src/app/**/layout.tsx", // Next.js layout boilerplate
      ],
      thresholds: {
        // Default-tier thresholds per ADR-0004
        global: { lines: 80, branches: 70 },
        // Critical paths: 90% line / 80% branch + mutation testing required
        "**/src/lib/auth/**": { lines: 90, branches: 80 },
        "**/src/app/api/feedback/**": { lines: 85, branches: 75 }, // user-facing per Standard 11
        // Utility paths: 60% line / 50% branch acceptable
        "**/src/lib/utils/**": { lines: 60, branches: 50 },
      },
    },
  },
});
