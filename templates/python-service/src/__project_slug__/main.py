"""FastAPI entry point for {{project_name}}.

Wires structured logging (per ADR-0009), Sentry, and OpenTelemetry instrumentation.
Exposes /health and /ready per ADR-0009 §7.
"""

from __future__ import annotations

import os
from contextlib import asynccontextmanager
from typing import AsyncIterator

import sentry_sdk
import structlog
from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from sentry_sdk.integrations.fastapi import FastApiIntegration

from {{project_slug}} import __version__


def _configure_logging() -> None:
    """Configure structured JSON logging per ADR-0009."""
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.add_log_level,
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            os.environ.get("LOG_LEVEL", "INFO").upper()
        ),
        cache_logger_on_first_use=True,
    )


def _configure_tracing(service_name: str) -> None:
    """Configure OTEL tracing per ADR-0009 §3."""
    endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT")
    if not endpoint:
        return  # Tracing disabled if endpoint not set

    resource = Resource.create({SERVICE_NAME: service_name})
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=endpoint)))
    trace.set_tracer_provider(provider)


def _configure_sentry() -> None:
    """Configure Sentry per ADR-0009 §4."""
    dsn = os.environ.get("SENTRY_DSN")
    if not dsn:
        return  # Sentry disabled if DSN not set

    sentry_sdk.init(
        dsn=dsn,
        integrations=[FastApiIntegration()],
        environment=os.environ.get("DEPLOY_ENV", "unknown"),
        release=os.environ.get("RELEASE_VERSION", __version__),
        traces_sample_rate=float(os.environ.get("SENTRY_TRACES_SAMPLE_RATE", "0.1")),
    )


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """App lifecycle — startup wires observability per ADR-0009."""
    _configure_logging()
    _configure_tracing(app.title)
    _configure_sentry()
    log = structlog.get_logger()
    log.info("startup", version=__version__, env=os.environ.get("DEPLOY_ENV", "unknown"))
    yield
    log.info("shutdown")


app = FastAPI(
    title="{{project_slug}}",
    version=__version__,
    lifespan=lifespan,
)
FastAPIInstrumentor.instrument_app(app)


@app.get("/health")
async def health() -> dict[str, str]:
    """Liveness probe — process responsive."""
    return {"status": "ok"}


@app.get("/ready")
async def ready() -> dict[str, str]:
    """Readiness probe — ready to serve traffic.

    Add real readiness checks (DB connectivity, deps reachable) as the project grows.
    """
    return {"status": "ready"}


@app.get("/")
async def root() -> dict[str, str]:
    """Hello-world entry point. Replace with real routes."""
    return {"name": "{{project_name}}", "version": __version__}
