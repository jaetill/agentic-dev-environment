/**
 * Structured logging per ADR-0009 §1.
 *
 * JSON output with OTEL semantic-convention field names. Trace context auto-merged
 * when OpenTelemetry is initialized (per src/lib/instrumentation.ts).
 *
 * PII redaction (per ADR-0006) is consumer-responsibility — fields tagged as PII
 * in the data model schema must NOT be passed to logger calls; pass hashes/IDs
 * instead. The `redactPII` helper here is a defense-in-depth fallback.
 */

import pino from 'pino';
import { trace, context } from '@opentelemetry/api';

const isDev = process.env.NODE_ENV === 'development';
const logLevel = process.env.LOG_LEVEL ?? (isDev ? 'debug' : 'info');

const logger = pino({
  level: logLevel,
  // OTEL semantic-convention field names per ADR-0009 §1
  formatters: {
    level: (label) => ({ severity_text: label.toUpperCase() }),
    log: (object) => {
      const span = trace.getSpan(context.active());
      if (span) {
        const { traceId, spanId } = span.spanContext();
        return { ...object, trace_id: traceId, span_id: spanId };
      }
      return object;
    },
  },
  base: {
    'service.name': process.env.OTEL_SERVICE_NAME ?? '{{project_slug}}',
    'service.version': process.env.npm_package_version ?? 'unknown',
    'deployment.environment': process.env.DEPLOY_ENV ?? 'local',
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  // Pretty-print only in dev for human readability
  ...(isDev
    ? {
        transport: {
          target: 'pino-pretty',
          options: {
            colorize: true,
            translateTime: 'HH:MM:ss',
            ignore: 'pid,hostname,trace_id,span_id,service.name,service.version,deployment.environment',
          },
        },
      }
    : {}),
});

/**
 * Helper: redact PII fields from a record before logging.
 * Use when you must log a record that may contain PII; better to not pass
 * PII-tagged fields at all.
 */
const PII_FIELD_NAMES = new Set(['email', 'name', 'displayName', 'phone', 'ssn', 'password']);

export function redactPII<T extends Record<string, unknown>>(record: T): T {
  const redacted = { ...record };
  for (const key of Object.keys(redacted)) {
    if (PII_FIELD_NAMES.has(key)) {
      redacted[key as keyof T] = '[REDACTED]' as T[keyof T];
    }
  }
  return redacted;
}

export { logger };
