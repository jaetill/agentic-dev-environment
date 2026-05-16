#!/usr/bin/env bash
# Build the test fixture Lambda zip.
# Usage: ./build.sh   (from this directory)

set -euo pipefail

cd "$(dirname "$0")"
rm -f ../hello-lambda.zip
zip -q ../hello-lambda.zip main.py
echo "Built ../hello-lambda.zip"
