import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false, // Don't advertise Next.js version
  experimental: {
    typedRoutes: true, // Type-safe route paths
  },
  // Production source maps for Sentry per ADR-0009
  productionBrowserSourceMaps: true,
};

export default withSentryConfig(nextConfig, {
  // Sentry build-time options per ADR-0009 §4
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  silent: !process.env.CI,
  widenClientFileUpload: true,
  hideSourceMaps: true, // After upload to Sentry, strip from public bundle
  disableLogger: true, // Strip Sentry SDK logger from production bundle
  automaticVercelMonitors: true,
});
