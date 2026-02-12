# flutter_application_1

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Deploy Web to GitHub Pages

This repo includes a GitHub Actions workflow at `.github/workflows/deploy_web.yml`.

Setup once on GitHub:

1. Push this project to a GitHub repository and use the `main` branch.
2. Open repository `Settings` -> `Pages`.
3. Set Source to `GitHub Actions`.

After setup:

1. Push commits to `main`.
2. Workflow `Deploy Flutter Web to GitHub Pages` runs automatically.
3. Open the deployed site URL from the Actions/Pages page.

## Local Gateway Backend (Hide API Tokens)

This repo now includes a minimal backend gateway at `server/main.dart`.
Use it to keep insurer API tokens on the server side (not in Flutter Web).

API contract doc:

- `server/API_CONTRACT.md`

### 1) Start gateway server (local)

```bash
PORT=8080 dart run server/main.dart
```

Optional env vars for upstream forwarding:

- `INSURER_UPSTREAM_BASE_URL` (example: `https://your-api-gateway.example.com`)
- `INSURER_UPSTREAM_TIMEOUT_MS` (default: `12000`)
- `INSURER_UPSTREAM_MAX_ATTEMPTS` (default: `3`)
- `INSURER_UPSTREAM_RETRY_BASE_DELAY_MS` (default: `250`)
- `GATEWAY_MAX_REQUEST_BODY_BYTES` (default: `131072`)
- `GATEWAY_API_KEY` (optional: when set, request must send `x-gateway-api-key`)
- `GATEWAY_ADMIN_API_KEY` (optional: when set, admin routes require `x-admin-api-key`)
- `GATEWAY_ADMIN_WRITE_API_KEY` (optional: when set, admin DELETE requires `x-admin-write-api-key`)
- `GATEWAY_DATA_FILE_PATH` (default: `server/data/discovery_records.json`)
- `GATEWAY_AUDIT_MAX_RECORDS` (default: `2000`)
- `INSURER_API_TOKEN_DEFAULT`
- `INSURER_API_TOKEN_CATHAY`, `INSURER_API_TOKEN_FUBON`, ...

Health check:

```bash
curl http://localhost:8080/health
```

### 2) Start gateway server (Docker)

```bash
docker build -f server/Dockerfile -t insurance-gateway .
docker run --rm -p 8080:8080 --env-file server/.env.example insurance-gateway
```

### 3) Start Flutter Web with backend base URL

```bash
flutter run -d chrome --dart-define=INSURER_API_BASE_URL=http://localhost:8080
```

### 4) Open Admin Dashboard UI

- In app: click the app bar `後台管理` icon.
- Direct route: `http://localhost:xxxxx/#/admin` (Flutter Web debug URL).

Notes:

- Admin UI is shown by default in debug mode. For release builds, enable it with:
  `--dart-define=ADMIN_UI_ENABLED=true`

### Quick scripts

```bash
# Start gateway only
./scripts/start_gateway.sh

# Smoke test gateway
./scripts/smoke_test_gateway.sh

# Run web with gateway base URL
./scripts/run_web_with_gateway.sh

# Start gateway + run web in one command
./scripts/dev_web_stack.sh
```

### Backend contract tests

```bash
flutter test test/server/gateway_contract_test.dart
```

### Admin routes (discovery audit records)

```bash
# List records
curl http://localhost:8080/v1/admin/discovery-records

# Stats
curl http://localhost:8080/v1/admin/discovery-records/stats

# Clear records
curl -X DELETE http://localhost:8080/v1/admin/discovery-records
```

Notes:

- Frontend no longer sends insurer tokens.
- Backend adds bearer token when calling upstream (if configured).
- If upstream is not configured, backend returns a local fallback response.
- Discovery requests are persisted to the local data file for admin queries.
- Gateway logs JSON lines for request/outbound retry events.
