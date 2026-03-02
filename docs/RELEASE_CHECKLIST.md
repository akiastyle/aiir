# Release Checklist

## Pre-release
- [ ] `lockdown-perms.sh` executed
- [ ] `build-native-runtime.sh` OK
- [ ] `smoke-runtime.sh` OK
- [ ] `backup-state.sh` OK
- [ ] documentation updated

## Security
- [ ] peer trust/revoke tested
- [ ] anti-replay verified
- [ ] signed-time window verified
- [ ] deny-by-default policy confirmed
- [ ] capability token checks verified (`smoke-capability.sh`)
- [ ] gateway human-indirect DB mode verified (`ai-gateway.env`)

## Publish
- [ ] clean commit state
- [ ] version tag created
- [ ] release notes written (changes, risks, rollback)
