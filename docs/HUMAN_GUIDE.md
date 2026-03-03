# Human Integrator Guide

## Purpose
This guide is for operators integrating AIIR on a server without handling internal AI2AI implementation details.

## Minimum Requirements
- Linux
- C toolchain (`cc`, `make`)
- `openssl`, `curl`, `sha256sum`
- optional web server (nginx/apache)

## Quick Bootstrap
```bash
/var/www/aiir/server/scripts/lockdown-perms.sh
/var/www/aiir/ai/bootstrap.sh
/var/www/aiir/server/scripts/smoke-runtime.sh
```

## Runtime Base Endpoints
- `GET /health`
- `GET /ai/meta`

## Human DB Mode (Indirect)
- You do not manage DB users/passwords.
- You request project/data actions, AIIR handles DB provisioning and execution in background.
- References like `project_ref` and `db_ref` are returned to you; credentials remain internal.
- Multiple projects can run on the same server, each with a dedicated `db_ref`.
- Contract:
  - `/var/www/aiir/docs/AIIR_GATEWAY_V1.md`
  - `/var/www/aiir/docs/HUMAN_ACTIONS_V1.md`

## HAL v1 (Intent -> Contract)
- `create_project` -> `POST /aiir/project/create`
- `save_data` -> `POST /aiir/db/exec` (write op)
- `read_data` -> `POST /aiir/db/exec` (read op)
- `project_status` -> `GET /health` + project refs/status

## Browser Access Code (Plugin-friendly)
- Generate time-bound access code from CLI:
  - `/var/www/aiir/server/scripts/generate-browser-access-code.sh <project_ref> [days] [scope]`
- Guide:
  - `/var/www/aiir/docs/HUMAN_BROWSER_ACCESS_V1.md`

## I18N and Direction
- Translation is AI-managed at runtime based on browser locale.
- Direction is handled automatically (`LTR` / `RTL`) by language.
- Policy:
  - `/var/www/aiir/docs/I18N_AI_POLICY_V1.md`

## Secure Default Policy
- DB exec disabled
- no wildcard ops
- signed-package import only

## Daily Operations
- state backup:
```bash
/var/www/aiir/server/scripts/backup-state.sh
```
- state restore:
```bash
/var/www/aiir/server/scripts/restore-state.sh <archive.tar.gz>
```
- runtime probe:
```bash
/var/www/aiir/server/scripts/check-runtime.sh
```

## What Not to Do
- do not copy private keys between servers
- do not enable `AI_POLICY_ALLOW_OPS='*'` in production
- do not disable signature/replay checks on import
