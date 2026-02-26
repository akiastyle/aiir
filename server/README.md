# AIIR Server Bridge (Apache/Nginx)

This path contains deployment assets to expose the native runtime behind Apache or Nginx.

## Runtime
- Single native binary: `/var/www/aiir/ai/toolchain-native/aiird`
- Default bind: `127.0.0.1:7788`
- Env file: `/var/www/aiir/server/env/ai-runtime.env`
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
- To enable DB exec explicitly:
  - `AI_POLICY_ALLOW_DB_EXEC=1`
  - `AI_POLICY_ALLOW_OPS='*'` or explicit allowlist like `AI_POLICY_ALLOW_OPS='1001,2001'`

## Health Payload
- `/health` reports:
  - `driftCount`, `checks`
  - `policy.allowDbExec`, `policy.allowAllOps`
  - `state.walPath`, `state.walExists`, `state.snapshotPath`, `state.snapshotExists`

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
  - verifica firma su `package.sig.payload` (metadata + digest di `package.sha256`)
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
