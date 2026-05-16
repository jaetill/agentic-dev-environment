export interface AliasParts {
  baseEmail: string;
  project: string;
  runId: string;
  testName?: string;
}

const SAFE_SEGMENT = /[^a-zA-Z0-9_]+/g;

/** Sanitize a single alias segment: alphanumeric and underscore preserved, all else → hyphen. */
function sanitizeSegment(segment: string): string {
  return segment.replace(SAFE_SEGMENT, "-").replace(/^-+|-+$/g, "");
}

/**
 * Build a plus-aliased Gmail address:
 *   `${local}+${project}-${runId}[-${testName}]@${domain}`
 *
 * Throws if `baseEmail` doesn't contain a single `@`. Each segment is
 * sanitized so the result is RFC-valid.
 */
export function buildAliasAddress(parts: AliasParts): string {
  const atIdx = parts.baseEmail.indexOf("@");
  if (atIdx <= 0 || atIdx !== parts.baseEmail.lastIndexOf("@")) {
    throw new Error(`baseEmail must contain exactly one @: ${parts.baseEmail}`);
  }
  const local = parts.baseEmail.slice(0, atIdx);
  const domain = parts.baseEmail.slice(atIdx + 1);
  if (local.includes("+")) {
    throw new Error(`baseEmail must not already contain a + alias: ${parts.baseEmail}`);
  }

  const project = sanitizeSegment(parts.project);
  const runId = sanitizeSegment(parts.runId);
  if (!project || !runId) {
    throw new Error("project and runId must produce non-empty sanitized segments");
  }

  const aliasParts = [project, runId];
  if (parts.testName) {
    const testName = sanitizeSegment(parts.testName);
    if (testName) aliasParts.push(testName);
  }

  return `${local}+${aliasParts.join("-")}@${domain}`;
}

/** Reverse of `buildAliasAddress` — extracts parts. Returns null for malformed input. */
export function parseAliasAddress(address: string): AliasParts | null {
  const atIdx = address.indexOf("@");
  if (atIdx <= 0) return null;
  const local = address.slice(0, atIdx);
  const domain = address.slice(atIdx + 1);
  const plusIdx = local.indexOf("+");
  if (plusIdx < 0) return null;

  const baseLocal = local.slice(0, plusIdx);
  const aliasBody = local.slice(plusIdx + 1);
  const segments = aliasBody.split("-");
  if (segments.length < 2) return null;

  const [project, runId, ...rest] = segments;
  const result: AliasParts = {
    baseEmail: `${baseLocal}@${domain}`,
    project: project!,
    runId: runId!,
  };
  if (rest.length > 0) {
    result.testName = rest.join("-");
  }
  return result;
}
