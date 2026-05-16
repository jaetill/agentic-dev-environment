"""Minimal Lambda handler used by lambda_base_test integration test.

Returns 200 from any path; logs structured JSON to verify CloudWatch wiring.
"""

from __future__ import annotations

import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event: dict, context: object) -> dict:  # noqa: ARG001
    """API Gateway v2 handler."""
    logger.info(json.dumps({"event": "request", "path": event.get("rawPath", "/")}))
    return {
        "statusCode": 200,
        "body": json.dumps({"status": "ok", "release": os.environ.get("RELEASE_VERSION", "unknown")}),
        "headers": {"content-type": "application/json"},
    }
