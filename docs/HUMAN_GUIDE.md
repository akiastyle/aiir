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
