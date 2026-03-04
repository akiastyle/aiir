# AIIR Server Bridge (Apache/Nginx)

This path contains deployment assets to expose the native runtime behind Apache or Nginx.

## Runtime
- Single native binary: `/var/www/aiir/ai/toolchain-native/aiird`
- Default bind: `127.0.0.1:7788`
- Env file: `/var/www/aiir/server/env/ai-runtime.env`
- Gateway env file (project/db contracts):
  - `/var/www/aiir/server/env/ai-gateway.env`
- Build script:
  - `/var/www/aiir/server/scripts/build-native-runtime.sh`
- Native AIIR toolchain:
  - `/var/www/aiir/ai/toolchain-native/aiird`
  - full rebuild: `/var/www/aiir/ai/rebuild.sh`
  - zero-touch bootstrap: `/var/www/aiir/ai/bootstrap.sh`
  - conformance/fuzz: `/var/www/aiir/ai/toolchain-native/aiird conformance /var/www/aiir/ai/core 500`
  - static build: `/var/www/aiir/ai/toolchain-native/build-static.sh`

## Security Defaults
- `AI_POLICY_ALLOW_DB_EXEC` defaults to `false` (deny-by-default)
- `AI_POLICY_ALLOW_OPS` defaults to empty (no ops allowed)
- `AI_MAX_REQ_BYTES` and `AI_MAX_BODY_BYTES` cap request size
- `AI_IO_TIMEOUT_MS` caps read/write socket time per request
- `AI_RATE_LIMIT_RPS` caps requests per second
- `AI_CB_FAIL_THRESHOLD` and `AI_CB_COOLDOWN_SEC` enable circuit breaker on repeated runtime failures
- Optional AIIR capability enforcement for `/ai/db/exec`:
  - `AI_CAP_REQUIRE=1`
  - `AI_CAP_SECRET=<shared-secret>`
  - `AI_CAP_MAX_FUTURE_SEC=120` (max allowed token future skew)
- Structured runtime audit log:
  - `AI_AUDIT_LOG_PATH=/var/www/aiir/ai/log/runtime_audit.log`
- Structured request logging toggle:
  - `AI_LOG_REQUESTS=1` (default on)
- To enable DB exec explicitly:
  - `AI_POLICY_ALLOW_DB_EXEC=1`
  - `AI_POLICY_ALLOW_OPS='*'` or explicit allowlist like `AI_POLICY_ALLOW_OPS='1001,2001'`

## Health Payload
- `/health` reports:
  - `driftCount`, `checks`
  - `policy.allowDbExec`, `policy.allowAllOps`
  - `capability.required`, `capability.maxFutureSec`
  - `metrics.requestsTotal`, `metrics.responses2xx`, `metrics.responses4xx`, `metrics.responses5xx`
  - `audit.path`
  - `state.walPath`, `state.walExists`, `state.snapshotPath`, `state.snapshotExists`
- `/metrics` reports Prometheus-compatible runtime counters:
  - `aiir_runtime_requests_total`
  - `aiir_runtime_responses_2xx_total`, `_4xx_total`, `_5xx_total`
  - `aiir_runtime_rate_limited_total`, `aiir_runtime_circuit_open_total`
  - `aiir_runtime_db_exec_allow_total`, `aiir_runtime_db_exec_deny_total`
  - `aiir_runtime_capability_deny_total`
- `/openapi.json` reports a minimal OpenAPI 3.0 schema for runtime endpoints.

## DB exec capability headers (when `AI_CAP_REQUIRE=1`)
- `X-AIIR-Cap-Op`: operation id (`opId`)
- `X-AIIR-Cap-Exp`: unix timestamp expiry (seconds)
- `X-AIIR-Cap-Nonce`: one-time nonce (anti-replay, in-memory ring)
- `X-AIIR-Cap-Sig`: HMAC-SHA256 hex signature over message `op|exp|nonce` with shared secret key
- Signature helper command:
  - `/var/www/aiir/ai/toolchain-native/aiird cap-sign <secret> <op-id> <exp-ts> <nonce>`

## systemd
1. Copy unit:
   - `cp /var/www/aiir/server/systemd/aiir-runtime.service /etc/systemd/system/`
2. Apply runtime filesystem lockdown:
   - `/var/www/aiir/server/scripts/lockdown-perms.sh`
3. Reload + enable:
   - `systemctl daemon-reload`
   - `systemctl enable --now aiir-runtime`
4. Check:
   - `systemctl status aiir-runtime`

## systemd timers
- Backup service/timer:
  - `cp /var/www/aiir/server/systemd/aiir-state-backup.{service,timer} /etc/systemd/system/`
  - `systemctl daemon-reload`
  - `systemctl enable --now aiir-state-backup.timer`
- Smoke service/timer:
  - `cp /var/www/aiir/server/systemd/aiir-smoke.{service,timer} /etc/systemd/system/`
  - `systemctl daemon-reload`
  - `systemctl enable --now aiir-smoke.timer`

## No-systemd fallback
- Install cron schedule:
  - `/etc/cron.d/aiir-maintenance`
- Jobs:
  - daily backup at `03:17`
  - smoke checks at `06:00` and `18:00`

## Nginx
1. Install site config:
   - `ln -s /var/www/aiir/server/nginx/aiir-runtime.conf /etc/nginx/sites-enabled/aiir-runtime.conf`
2. Validate and reload:
   - `nginx -t && systemctl reload nginx`

## Apache
1. Enable modules:
   - `a2enmod proxy proxy_http headers rewrite`
2. Install site config:
   - `cp /var/www/aiir/server/apache/aiir-runtime.conf /etc/apache2/sites-available/aiir-runtime.conf`
3. Enable and reload:
   - `a2ensite aiir-runtime.conf`
   - `apachectl configtest && systemctl reload apache2`

## Local check
- Start manually:
  - `/var/www/aiir/server/scripts/start-runtime.sh`
- Probe endpoints:
  - `/var/www/aiir/server/scripts/check-runtime.sh`
- Run smoke suite:
  - `/var/www/aiir/server/scripts/smoke-runtime.sh`
- Run capability smoke (allow + replay deny + expired deny):
  - `/var/www/aiir/server/scripts/smoke-capability.sh`

## AIIR Gateway v1 (project/db orchestration)
- Contract document:
  - `/var/www/aiir/docs/AIIR_GATEWAY_V1.md`
  - `/var/www/aiir/docs/HUMAN_ACTIONS_V1.md`
  - `/var/www/aiir/docs/HUMAN_BROWSER_ACCESS_V1.md`
  - `/var/www/aiir/docs/I18N_AI_POLICY_V1.md`
- Main endpoints:
  - `POST /aiir/project/create` (auto-provision DB by default)
  - `POST /aiir/db/exec` (AI-managed DB operation)
- Human mode:
  - indirect DB usage only (no direct credentials exposed)
- Multi-project mode:
  - each project gets a dedicated `db_ref`; multiple projects/DBs can coexist on the same server
- Gateway smoke:
  - `/var/www/aiir/server/scripts/smoke-gateway.sh`
- Provision helper (project + DB + env + policy + domain web conf):
  - `/var/www/aiir/server/scripts/provision-project-domain.sh <project-name> [domain]`
  - optional system install/reload: `AIIR_PROVISION_APPLY=1`
- Zero-conf bootstrap (AI-first):
  - `/var/www/aiir/server/scripts/aiir-up.sh`
  - optional project bootstrap:
    - `/var/www/aiir/server/scripts/aiir-up.sh --project <name> --type <project-type> [--domain <domain>] [--apply-web]`
- Zero-conf stop:
  - `/var/www/aiir/server/scripts/aiir-down.sh`
  - returns non-zero if runtime is still reachable after stop attempt
- Runtime diagnostics:
  - `/var/www/aiir/server/scripts/aiir-doctor.sh`
  - strict mode (non-zero on warnings/failures):
    - `/var/www/aiir/server/scripts/aiir-doctor.sh --strict`
- Operational chat CLI (human talks only to AI layer):
  - `/var/www/aiir/server/scripts/aiir-chat.sh "help"`
  - `/var/www/aiir/server/scripts/aiir-chat.sh "stato"`
  - `/var/www/aiir/server/scripts/aiir-chat.sh "crea progetto crm-alpha tipo webapp dominio crm.local"`
  - `/var/www/aiir/server/scripts/aiir-chat.sh "ui progetto crm-alpha preset material"`
- Official unified CLI (recommended):
  - `/var/www/aiir/server/scripts/aiir up`
  - `/var/www/aiir/server/scripts/aiir chat "stato"`
  - `/var/www/aiir/server/scripts/aiir down`
  - `/var/www/aiir/server/scripts/aiir doctor --strict`
  - `/var/www/aiir/server/scripts/aiir optimize <project-ref|project-name>`
  - `/var/www/aiir/server/scripts/aiir ui <project-ref|project-name> [utility|material|bootstrap-like]`
- Chat intents:
  - `stato`
  - `lista progetti`
  - `stato progetto <project-ref|project-name>`
  - `crea progetto <name> tipo <type> dominio <domain>`
  - `ottimizza progetto <project-ref|project-name>`
  - `ui progetto <project-ref|project-name> preset <utility|material|bootstrap-like>`
  - `ferma runtime conferma`
  - destructive intents require `conferma/confirm`
  - project type mapping is centralized in:
    - `/var/www/aiir/server/scripts/project-type-map.sh`
- AI-only smoke (up/chat/optimize/doctor/down):
  - `/var/www/aiir/server/scripts/smoke-ai-ops.sh`
- UI preset assets:
  - `/var/www/aiir/server/ui-presets/`
- Browser access code generator (default 30d):
  - `/var/www/aiir/server/scripts/generate-browser-access-code.sh <project_ref> [days] [scope]`
- File versioning index and changelog generator:
  - `/var/www/aiir/server/scripts/update-file-version-index.sh`
  - outputs:
    - `/var/www/aiir/docs/FILE_VERSION_INDEX.csv`
    - `/var/www/aiir/docs/CHANGELOG_AIIR.md`
- Benchmark dashboard:
  - generator: `/var/www/aiir/test/aiir-benchmark-dashboard.sh`
  - output: `/var/www/aiir/test/OPEN_REPO_DASHBOARD.md`
- AI operations runbook:
  - `/var/www/aiir/docs/AI_OPERATIONS_RUNBOOK.md`

## State backup (rotation)
- Manual backup:
  - `/var/www/aiir/server/scripts/backup-state.sh`
- Custom retention:
  - `/var/www/aiir/server/scripts/backup-state.sh /var/www/aiir/ai/state /var/backups/aiir-state 7`
- Restore from archive:
  - `/var/www/aiir/server/scripts/restore-state.sh /var/backups/aiir-state/state-YYYYMMDD-HHMMSS.tar.gz`

## AI2AI keying and trust
- Initialize local node identity + signing key:
  - `/var/www/aiir/ai/exchange/init-signing-key.run.sh`
- Bootstrap node state (auto `isolated` if no peers, `paired` if trust store non-empty):
  - `/var/www/aiir/ai/exchange/bootstrap-node.run.sh`
- On standard bootstrap this is executed automatically:
  - `/var/www/aiir/ai/bootstrap.sh`
- Trust a peer AI public key:
  - `/var/www/aiir/ai/exchange/trust-add-peer.run.sh <peer-id> <peer-pub.pem>`
- Revoke a peer AI:
  - `/var/www/aiir/ai/exchange/trust-revoke-peer.run.sh <peer-id>`
- Build signed package:
  - `/var/www/aiir/ai/exchange/build-package.run.sh <src-dir> <package-dir> <core-dir>`
- Verify + unpack signed package:
  - `/var/www/aiir/ai/exchange/unpack-package.run.sh <package-dir> <out-dir>`
  - verifies signature on `package.sig.payload` (metadata + digest of `package.sha256`)
- Sync wrapper:
  - `/var/www/aiir/ai/exchange/sync-core.run.sh build <src-dir> <package-dir> [core-dir]`
  - `/var/www/aiir/ai/exchange/sync-core.run.sh apply <package-dir> <out-dir>`
- Onboarding bundle generated in:
  - `/var/www/aiir/ai/state/onboarding/`
- Import anti-replay ledger:
  - `/var/www/aiir/ai/state/import-ledger.log`
- Signed-time window (default):
  - `AIIR_SIGNED_AT_MAX_AGE_SEC=86400`
  - `AIIR_SIGNED_AT_MAX_FUTURE_SEC=300`

## Minimal Container
- Dockerfile:
  - `/var/www/aiir/server/container/Dockerfile`
