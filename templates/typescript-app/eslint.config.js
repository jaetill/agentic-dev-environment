// ESLint flat config per ADR-0005 — pragmatic strict.
// Uses eslint:recommended + typescript-eslint:recommended-type-checked + plugins.

import js from "@eslint/js";
import tseslint from "typescript-eslint";
import nextPlugin from "@next/eslint-plugin-next";
import importPlugin from "eslint-plugin-import";
import unusedImports from "eslint-plugin-unused-imports";
import promise from "eslint-plugin-promise";

export default tseslint.config(
  {
    ignores: [
      "node_modules/",
      ".next/",
      "out/",
      "dist/",
      "coverage/",
      "playwright-report/",
      "*.config.{js,ts}",
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    plugins: {
      "@next/next": nextPlugin,
      import: importPlugin,
      "unused-imports": unusedImports,
      promise,
    },
    rules: {
      // Next.js recommended rules
      ...nextPlugin.configs.recommended.rules,
      ...nextPlugin.configs["core-web-vitals"].rules,

      // typescript-eslint additions
      "@typescript-eslint/consistent-type-imports": "error",
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/no-misused-promises": "error",
      "@typescript-eslint/strict-boolean-expressions": "warn",
      "@typescript-eslint/no-unnecessary-condition": "warn",
      "@typescript-eslint/prefer-nullish-coalescing": "error",
      "@typescript-eslint/prefer-optional-chain": "error",

      // Imports
      "unused-imports/no-unused-imports": "error",
      "import/order": [
        "error",
        {
          groups: ["builtin", "external", "internal", "parent", "sibling", "index"],
          "newlines-between": "always",
          alphabetize: { order: "asc", caseInsensitive: true },
        },
      ],

      // Promises
      "promise/always-return": "error",
      "promise/no-nesting": "warn",
      "promise/no-return-wrap": "error",

      // Code-quality gap (ADR-0005 §6) — judgment-based rules surfaced here:
      "complexity": ["warn", 10],
      "max-lines-per-function": ["warn", { max: 50, skipBlankLines: true, skipComments: true }],
      "max-params": ["warn", 5],
      "no-console": "warn", // use the structured logger per ADR-0009
    },
  },
  {
    // Test file relaxations
    files: ["tests/**/*.{ts,tsx}", "**/*.{test,spec}.{ts,tsx}"],
    rules: {
      "@typescript-eslint/no-explicit-any": "off",
      "max-lines-per-function": "off",
      "no-console": "off",
    },
  },
);
