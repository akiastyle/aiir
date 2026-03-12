# AI Operations Runbook

## Scope
AI-first runtime operations with minimal human interaction.

## Platform Focus
This runbook assumes AIIR server has two primary outcomes:
- AI sync reliability: trusted AI2AI exchange and repeatable contract alignment
- app delivery reliability: end-to-end creation, provisioning, deployment, and operation of production apps

Permanent principle reference:
- `/var/www/aiir/docs/AIIR_AI_FIRST_PRINCIPLES.md`

## Standard Flow

1. Bootstrap runtime (and optional project):
```bash
/var/www/aiir/server/scripts/aiir up
# optional:
/var/www/aiir/server/scripts/aiir up --project crm-alpha --type webapp --domain crm.local
# deploy-oriented one-shot (runtime + project + policy + web apply when possible):
/var/www/aiir/server/scripts/aiir deploy --project crm-alpha --type webapp --domain crm.local
# strict mode (fail if web apply cannot be installed/reloaded):
/var/www/aiir/server/scripts/aiir deploy --project crm-alpha --type webapp --domain crm.local --strict-web-apply
```

2. Operate via chat intents only:
```bash
/var/www/aiir/server/scripts/aiir chat "stato"
/var/www/aiir/server/scripts/aiir chat "help"
/var/www/aiir/server/scripts/aiir chat "lista progetti"
/var/www/aiir/server/scripts/aiir chat "stato progetto crm-alpha"
/var/www/aiir/server/scripts/aiir chat "ottimizza progetto crm-alpha"
/var/www/aiir/server/scripts/aiir chat "ui progetto crm-alpha preset material"
```

3. Diagnostics:
```bash
/var/www/aiir/server/scripts/aiir doctor
/var/www/aiir/server/scripts/aiir doctor --strict
/var/www/aiir/server/scripts/aiir verify
/var/www/aiir/server/scripts/aiir audit
```

4. Stop runtime (requires explicit confirmation in chat path):
```bash
/var/www/aiir/server/scripts/aiir chat "ferma runtime conferma"
# or direct:
/var/www/aiir/server/scripts/aiir down
```

5. Run end-to-end AI-only smoke:
```bash
/var/www/aiir/server/scripts/smoke-ai-ops.sh
/var/www/aiir/server/scripts/aiir contract
```

6. AI2AI migration flow (source -> AIIR -> parity):
```bash
/var/www/aiir/server/scripts/aiir ingest <source-dir> <out-dir> [project-id]
/var/www/aiir/server/scripts/aiir parity <source-dir> <out-dir>
# execute OAIIR web IR into runnable web output:
/var/www/aiir/server/scripts/aiir oaiir <out-dir> [runtime-out-dir]
```
Compatibility alias:
- `/var/www/aiir/server/scripts/aiir convert ...` (legacy alias of `ingest`)
Policy reference:
- `/var/www/aiir/docs/AI2AI_MIGRATION_POLICY_V1.md`

7. Benchmarks:
```bash
# quick MB-only
/var/www/aiir/server/scripts/aiir bench --profile quick
# full MB+parity (size-aware)
/var/www/aiir/server/scripts/aiir bench --profile full
# full fixed regression pack (canary set)
/var/www/aiir/server/scripts/aiir bench --profile full --regression-pack --gate-strict
# shortcut script for regression pack
/var/www/aiir/test/run-regression-pack.sh
# full with strict quality gates (AI-first hardening)
/var/www/aiir/server/scripts/aiir bench --profile full --gate-strict
# also require full analysis only (no chunk mode)
/var/www/aiir/server/scripts/aiir bench --profile full --gate-strict --gate-no-chunk
```
Full benchmark outputs:
- `/var/www/aiir/test/OPEN_REPO_FULL_LOG.csv`
- `/var/www/aiir/test/OPEN_REPO_FULL_LATEST.csv`
- `/var/www/aiir/test/OPEN_REPO_FULL_REPORT.md`
- `/var/www/aiir/test/OPEN_REPO_FULL_ARTIFACT_DELTA.csv`
- `/var/www/aiir/test/OPEN_REPO_FULL_PROFILE.csv`
- `/var/www/aiir/test/OPEN_REPO_FULL_PROFILE_REPORT.md`

8. Cleanup generated artifacts:
```bash
/var/www/aiir/server/scripts/aiir clean --safe
# includes test workdirs
/var/www/aiir/server/scripts/aiir clean --deep
```

9. Optional automation:
- systemd:
  - `aiir-smoke.timer` (twice daily AI-ops smoke)
  - `aiir-self-audit.timer` (hourly AI-first self-audit)
  - `aiir-contract-pack.timer` (daily contract pack)
- no-systemd:
  - `/var/www/aiir/server/cron/aiir-maintenance`
- one-shot setup:
  - `/var/www/aiir/server/scripts/aiir automate --mode auto --dry-run`

## Chat Error Codes
- `intent_unknown`
- `confirmation_required`
- `project_not_found`
- `type_map_missing`
- `projects_lib_missing`

## Notes
- Destructive intents are blocked unless `conferma/confirm` is present.
- Project type mapping is centralized in:
  - `/var/www/aiir/server/scripts/project-type-map.sh`
- Project metadata parsing is centralized in:
  - `/var/www/aiir/server/scripts/projects-ndjson-lib.sh`
- UI presets are stored in:
  - `/var/www/aiir/server/ui-presets/`
- Local write operations use a shared lock file:
  - `/var/www/aiir/ai/state/.ops.lock`
- Legacy human adapter is still available for compatibility, but deprecated:
  - removed; use chat flow only.
