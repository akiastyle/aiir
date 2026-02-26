# Release Checklist

## Pre-release
- [ ] `lockdown-perms.sh` eseguito
- [ ] `build-native-runtime.sh` OK
- [ ] `smoke-runtime.sh` OK
- [ ] `backup-state.sh` OK
- [ ] documentazione aggiornata

## Security
- [ ] peer trust/revoke testati
- [ ] anti-replay verificato
- [ ] signed_at window verificata
- [ ] policy default deny confermata

## Publish
- [ ] commit pulito
- [ ] tag versione creato
- [ ] note release scritte (cosa cambia, rischi, rollback)
