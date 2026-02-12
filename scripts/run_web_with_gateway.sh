#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY_BASE_URL="${GATEWAY_BASE_URL:-http://localhost:8080}"

echo "[web] using INSURER_API_BASE_URL=$GATEWAY_BASE_URL"

exec flutter run -d chrome \
  --dart-define="INSURER_API_BASE_URL=$GATEWAY_BASE_URL" \
  "$@"
