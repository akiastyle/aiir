# Human Browser Access v1

## Goal
Allow a human operator to connect from browser/plugin using a short-lived access code generated from CLI.

## Generate Code (default 30 days)

```bash
/var/www/aiir/server/scripts/generate-browser-access-code.sh <project_ref> [days] [scope]
```

Examples:

```bash
/var/www/aiir/server/scripts/generate-browser-access-code.sh prj_01J...
/var/www/aiir/server/scripts/generate-browser-access-code.sh prj_01J... 30 browser_connect
```

Output:
- one-time visible `code`
- `expires_at`
- bound `project_ref`

## Storage Model

- Codes are stored hashed (SHA-256), never in plain text
- Storage file (default):
  - `/var/www/aiir/ai/state/browser-access-codes.ndjson`

NDJSON entry example:
```json
{"created_at":"2026-03-02T21:00:00Z","expires_at":"2026-04-01T21:00:00Z","project_ref":"prj_...","scope":"browser_connect","code_sha256":"...","status":"active"}
```

## Plugin/Browser Flow

1. Human receives access code from CLI
2. Plugin sends code to AIIR gateway session endpoint (future runtime binding)
3. AIIR validates hash + expiry + project scope
4. AIIR issues short-lived session binding for browser workflow

## Security Notes

- No DB credentials are exposed
- Code validity is time-bounded (30d default, configurable)
- Use capability-gated execution for sensitive operations after session bootstrap
