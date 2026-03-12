# Release Checklist

## Pre-release
- [ ] permissions hardening executed (`chmod -R o-rwx /var/www/aiir/ai/state /var/www/aiir/server/env`)
- [ ] native runtime build OK (`/var/www/aiir/ai/toolchain-native/build-static.sh`)
- [ ] runtime verify OK (`/var/www/aiir/server/scripts/aiir verify --skip-contract`)
- [ ] backup rotation command OK (cron/systemd inline tar flow)
- [ ] documentation updated

## Security
- [ ] peer trust/revoke tested
- [ ] anti-replay verified
- [ ] signed-time window verified
- [ ] deny-by-default policy confirmed
- [ ] capability token checks verified (`/var/www/aiir/server/scripts/aiir contract --no-ai-ops`)
- [ ] gateway human-indirect DB mode verified (`ai-gateway.env`)
- [ ] gateway project/db flow verified (`/var/www/aiir/server/scripts/aiir contract --no-ai-ops`)
- [ ] project auto-provision script verified (`provision-project-domain.sh`)
- [ ] file version index/changelog policy reviewed (historical ledger may include removed files)
- [ ] browser access workflow verified (AI-managed, no direct human script)
- [ ] i18n AI policy validated (locale + RTL/LTR behavior)
- [ ] codec policy verified (`/var/www/aiir/server/env/ai-codec.env`)

## Publish
- [ ] clean commit state
- [ ] version tag created
- [ ] release notes written (changes, risks, rollback)
