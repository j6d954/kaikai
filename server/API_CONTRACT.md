# Gateway API Contract (v1)

This document defines the HTTP contract for the local insurer gateway in `server/main.dart`.

## Base URL

- Local default: `http://localhost:8080`

## Common Headers

- Request: `Content-Type: application/json` for JSON endpoints
- Response: `Content-Type: application/json`
- Response includes `x-request-id` header
- Optional request auth header: `x-gateway-api-key` (required only when `GATEWAY_API_KEY` is configured)
- Optional admin auth header: `x-admin-api-key` (required only when `GATEWAY_ADMIN_API_KEY` is configured)

## Supported Insurer Codes

- `cathay`
- `fubon`
- `nan_shan`
- `shin_kong`
- `taiwan_life`
- `china_life`
- `transglobe`
- `farglory`
- `mercuries`
- `yuanta`
- `pca`
- `first_life`

## 1) Health Check

### `GET /health`

Response `200`:

```json
{
  "status": "ok",
  "timestamp": "2026-02-12T00:00:00.000Z",
  "upstreamConfigured": false,
  "requestId": "req_..."
}
```

## 2) Policy Discovery

### `POST /v1/insurers/{insurerCode}/policies/discovery`

### Request Body

```json
{
  "customerReference": "cust-001",
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
```

### Request Validation Rules

- `customerReference`: required, non-empty string, max length `128`
- `knownPolicies`: required, must be a JSON array
- each item in `knownPolicies` must be a JSON object
- `targetInsurers`: optional, but if present must be an array of non-empty strings
- Request body size is limited by `GATEWAY_MAX_REQUEST_BODY_BYTES` (default `131072`)

### Discovery Response Schema

Returned for success/fallback/upstream failures (`2xx`, `5xx` from this endpoint):

```json
{
  "status": "found|no_data|unavailable|failed",
  "code": "string_error_or_result_code",
  "note": "human-readable note",
  "policies": [],
  "requestId": "req_..."
}
```

### Discovery `status` Values

- `found`: matching policies found
- `no_data`: request succeeded but no matching policy data
- `unavailable`: data source unavailable (for example token not configured)
- `failed`: technical failure while calling upstream

### Discovery `code` Examples

- `local_fallback_found`
- `local_fallback_no_data`
- `token_not_configured`
- `upstream_found`
- `upstream_no_data`
- `upstream_unavailable`
- `upstream_failed`
- `upstream_invalid_response`
- `upstream_timeout`
- `upstream_connect_failed`
- `upstream_call_failed`
- `upstream_retries_exhausted`

## 3) Admin Discovery Records

These routes read/write persisted discovery audit records.

### `GET /v1/admin/discovery-records`

Query params:

- `limit` (default `50`, max `500`)
- `offset` (default `0`)
- `insurerCode` (optional exact match)
- `status` (optional exact match: `found|no_data|unavailable|failed`)

Response `200`:

```json
{
  "items": [],
  "total": 0,
  "limit": 50,
  "offset": 0,
  "requestId": "req_..."
}
```

### `GET /v1/admin/discovery-records/{recordId}`

Response `200`:

```json
{
  "id": "req_...",
  "requestId": "req_...",
  "createdAt": "2026-02-12T00:00:00.000Z",
  "insurerCode": "cathay",
  "status": "found",
  "code": "local_fallback_found",
  "note": "Gateway 本機資料推估（未呼叫上游）",
  "responseStatusCode": 200,
  "source": "local_fallback",
  "customerReference": "cust-001",
  "knownPoliciesCount": 1,
  "targetInsurersCount": 0,
  "matchedPoliciesCount": 1
}
```

### `GET /v1/admin/discovery-records/stats`

Response `200`:

```json
{
  "total": 10,
  "byStatus": {
    "found": 7,
    "no_data": 2,
    "failed": 1
  },
  "byInsurerCode": {
    "cathay": 6,
    "fubon": 4
  },
  "requestId": "req_..."
}
```

### `DELETE /v1/admin/discovery-records`

Response `200`:

```json
{
  "removed": 10,
  "requestId": "req_..."
}
```

## Error Response Schema

Returned for validation/routing errors (`4xx`) and unexpected server errors (`500` outside discovery flow):

```json
{
  "code": "machine_readable_error_code",
  "message": "human-readable message",
  "requestId": "req_...",
  "details": {}
}
```

`details` is optional.

## HTTP Status Codes

- `200`: health/discovery success or fallback result
- `401`: missing/invalid gateway API key (when auth is enabled)
- `400`: invalid JSON or invalid payload
- `404`: unsupported insurer code or unknown route
- `413`: request body exceeds configured max bytes
- `405`: method not allowed for route
- `500`: unhandled server error
- `502`: upstream bad gateway / invalid upstream response
- `504`: upstream timeout after retries

## Standard Error Codes

- `invalid_json_body`
- `invalid_payload`
- `unauthorized`
- `admin_unauthorized`
- `unsupported_insurer`
- `payload_too_large`
- `method_not_allowed`
- `invalid_record_id`
- `record_not_found`
- `not_found`
- `internal_error`
