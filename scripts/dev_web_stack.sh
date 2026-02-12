#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8080}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/server/.env}"
GATEWAY_LOG_FILE="${GATEWAY_LOG_FILE:-$ROOT_DIR/.gateway.log}"

echo "[stack] starting gateway on port $PORT"
PORT="$PORT" ENV_FILE="$ENV_FILE" "$ROOT_DIR/scripts/start_gateway.sh" >"$GATEWAY_LOG_FILE" 2>&1 &
GW_PID=$!

cleanup() {
  if [[ -n "${GW_PID:-}" ]]; then
    kill "$GW_PID" >/dev/null 2>&1 || true
    wait "$GW_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

for _ in $(seq 1 80); do
  if curl -fsS "http://localhost:$PORT/health" >/dev/null; then
    break
  fi
  sleep 0.2
done

if ! curl -fsS "http://localhost:$PORT/health" >/dev/null; then
  echo "[stack] gateway did not become ready; check $GATEWAY_LOG_FILE"
  exit 1
fi

echo "[stack] gateway ready (log: $GATEWAY_LOG_FILE)"
GATEWAY_BASE_URL="http://localhost:$PORT" \
  "$ROOT_DIR/scripts/run_web_with_gateway.sh" "$@"
