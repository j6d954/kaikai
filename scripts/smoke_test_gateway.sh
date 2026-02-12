#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_PORT="${TEST_PORT:-8099}"
LOG_FILE="$(mktemp -t gateway-smoke-log.XXXXXX)"
RESP_FILE="$(mktemp -t gateway-smoke-resp.XXXXXX)"
PAYLOAD_FILE="$RESP_FILE.payload"

cleanup() {
  if [[ -n "${GW_PID:-}" ]]; then
    kill "$GW_PID" >/dev/null 2>&1 || true
    wait "$GW_PID" 2>/dev/null || true
  fi
  rm -f "$RESP_FILE"
  rm -f "$PAYLOAD_FILE"
}
trap cleanup EXIT

echo "[smoke] starting gateway on port $TEST_PORT"
PORT="$TEST_PORT" INSURER_UPSTREAM_BASE_URL="${INSURER_UPSTREAM_BASE_URL:-}" \
  INSURER_API_TOKEN_DEFAULT="${INSURER_API_TOKEN_DEFAULT:-}" \
  dart run "$ROOT_DIR/server/main.dart" >"$LOG_FILE" 2>&1 &
GW_PID=$!

HEALTH_OK=0
for _ in $(seq 1 50); do
  if curl -fsS "http://localhost:$TEST_PORT/health" >/dev/null 2>&1; then
    HEALTH_OK=1
    break
  fi
  sleep 0.2
done

if [[ "$HEALTH_OK" -ne 1 ]]; then
  echo "[smoke] failed: gateway health check timeout"
  echo "--- gateway log ---"
  cat "$LOG_FILE"
  exit 1
fi

echo "[smoke] health check passed"

cat >"$PAYLOAD_FILE" <<'JSON'
{
  "customerReference": "smoke-001",
  "targetInsurers": ["國泰人壽"],
  "knownPolicies": [
    {
      "id": "p1",
      "type": "壽險",
      "insurer": "國泰人壽",
      "coverageAmount": 500,
      "monthlyPremium": 2500,
      "paymentDay": 5,
      "effectiveDate": "2024-01-01T00:00:00.000",
      "expiryDate": null,
      "note": ""
    }
  ]
}
JSON

HTTP_CODE=$(curl -sS -o "$RESP_FILE" -w "%{http_code}" \
  -X POST "http://localhost:$TEST_PORT/v1/insurers/cathay/policies/discovery" \
  -H "Content-Type: application/json" \
  --data @"$PAYLOAD_FILE")

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "[smoke] failed: discovery status code = $HTTP_CODE"
  echo "--- response ---"
  cat "$RESP_FILE"
  echo
  echo "--- gateway log ---"
  tail -n 50 "$LOG_FILE"
  exit 1
fi

if ! rg -q '"status":"(found|no_data|unavailable|failed)"' "$RESP_FILE"; then
  echo "[smoke] failed: discovery response schema mismatch"
  echo "--- response ---"
  cat "$RESP_FILE"
  echo
  exit 1
fi

echo "[smoke] discovery response:"
cat "$RESP_FILE"
echo
echo "[smoke] passed"
