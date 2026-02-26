# Human Integrator Guide

## Scopo
Questa guida serve a chi integra AIIR in un server applicativo senza entrare nel dettaglio interno AI2AI.

## Requisiti minimi
- Linux
- compilatore C (`cc`, `make`)
- `openssl`, `curl`, `sha256sum`
- web server opzionale (nginx/apache)

## Bootstrap rapido
```bash
/var/www/aiir/server/scripts/lockdown-perms.sh
/var/www/aiir/ai/bootstrap.sh
/var/www/aiir/server/scripts/smoke-runtime.sh
```

## Endpoint base runtime
- `GET /health`
- `GET /ai/meta`

## Policy default (sicure)
- DB exec disabilitato
- no op wildcard
- import solo pacchetti firmati

## Operazioni quotidiane
- backup stato:
```bash
/var/www/aiir/server/scripts/backup-state.sh
```
- restore stato:
```bash
/var/www/aiir/server/scripts/restore-state.sh <archive.tar.gz>
```
- controllo runtime:
```bash
/var/www/aiir/server/scripts/check-runtime.sh
```

## Cosa non fare
- non copiare chiavi private tra server
- non abilitare `AI_POLICY_ALLOW_OPS='*'` in produzione
- non disabilitare firma/replay check in import
