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
/bin/chmod -R o-rwx /var/www/aiir/ai/state /var/www/aiir/server/env
/var/www/aiir/ai/bootstrap.sh
/var/www/aiir/server/scripts/aiir verify --skip-contract
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

## Project Type Adapter (Human-Only)
- Keep runtime generic: select project type through AI chat intent.
- Preferred command:
  - `/var/www/aiir/server/scripts/aiir chat "crea progetto <name> tipo <type> dominio <domain>"`

## Browser Access (Plugin-friendly)
- Human access bootstrap is AI-managed via chat intents.
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
/bin/bash -lc 'mkdir -p /var/backups/aiir-state && ts=$(date -u +%Y%m%d-%H%M%S) && tar -czf /var/backups/aiir-state/state-${ts}.tar.gz /var/www/aiir/ai/state && ls -1t /var/backups/aiir-state/state-*.tar.gz | tail -n +15 | xargs -r rm -f'
```
- state restore:
```bash
tar -xzf <archive.tar.gz> -C /
```
- runtime probe:
```bash
/var/www/aiir/server/scripts/check-runtime.sh
```

## What Not to Do
- do not copy private keys between servers
- do not enable `AI_POLICY_ALLOW_OPS='*'` in production
- do not disable signature/replay checks on import
