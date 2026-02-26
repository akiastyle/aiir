# AIIR

AIIR is an AI-first runtime with secure AI2AI package exchange, deny-by-default policy, and a hardened synchronization pipeline.

Goals:
- keep the AI core autonomous
- separate runtime, state, and security concerns
- enable interoperable AI-to-AI exchange through signed packages

Structure:
- `ai/`: AI core, native runtime, exchange, keys, state
- `server/`: operational bridge (scripts, env, systemd/nginx/apache, smoke/backup)
- `human/`: non-core area (optional)

Documentation:
- Git publishing guide: `docs/GIT_PUBLISHING.md`
- Human integrator guide: `docs/HUMAN_GUIDE.md`
- AI2AI handoff guide: `docs/AI2AI_HANDOFF.md`
- Release checklist: `docs/RELEASE_CHECKLIST.md`

## Why AIIR
- secure AI2AI exchange with per-node signing
- explicit peer trust with immediate revocation
- anti-replay protection and signed-time window on imports
- native C runtime with deny-by-default policy
- server-ready operations with smoke, backup, and restore

## Quickstart
```bash
/var/www/aiir/server/scripts/lockdown-perms.sh
/var/www/aiir/ai/bootstrap.sh
/var/www/aiir/server/scripts/smoke-runtime.sh
```

## Security Baseline
- `AI_POLICY_ALLOW_DB_EXEC=0`
- `AI_POLICY_ALLOW_OPS=` (empty)
- peer trust/revoke: `trust-add-peer.run.sh` / `trust-revoke-peer.run.sh`
- anti-replay ledger: `ai/state/import-ledger.log`
- signed-time window:
  - `AIIR_SIGNED_AT_MAX_AGE_SEC`
  - `AIIR_SIGNED_AT_MAX_FUTURE_SEC`

## Discoverability
- `llms.txt` for AI-friendly indexing
- `aiir.repo.json` for machine-readable metadata
