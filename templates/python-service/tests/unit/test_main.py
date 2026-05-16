"""Unit tests for the FastAPI app entry point."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from {{project_slug}}.main import app


@pytest.fixture
def client() -> TestClient:
    """Provide a FastAPI test client."""
    return TestClient(app)


def test_health_returns_ok(client: TestClient) -> None:
    """The /health endpoint returns 200 with status=ok."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready_returns_ready(client: TestClient) -> None:
    """The /ready endpoint returns 200 with status=ready."""
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_root_returns_project_metadata(client: TestClient) -> None:
    """The root endpoint returns the project name and version."""
    response = client.get("/")
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "{{project_name}}"
    assert "version" in body
