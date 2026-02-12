#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/server/.env}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  echo "[gateway] env file not found: $ENV_FILE (using current env)"
fi

PORT="${PORT:-8080}"
export PORT

echo "[gateway] starting on http://localhost:$PORT"
exec dart run "$ROOT_DIR/server/main.dart"
