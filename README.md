# AIIR

AIIR e' un runtime AI-first con scambio AI2AI firmato, policy deny-by-default e pipeline di sincronizzazione core.

Obiettivo:
- mantenere il core AI autonomo
- separare runtime/stato/sicurezza
- consentire interoperabilita' tra AI tramite pacchetti firmati

Struttura:
- `ai/`: core AI, runtime nativo, exchange, chiavi, stato
- `server/`: bridge operativo (script, env, systemd/nginx/apache, smoke/backup)
- `human/`: area non core AI (opzionale)

Documentazione:
- guida Git publishing: `docs/GIT_PUBLISHING.md`
- guida per human integrator: `docs/HUMAN_GUIDE.md`
- handoff AI2AI: `docs/AI2AI_HANDOFF.md`
- checklist rilascio: `docs/RELEASE_CHECKLIST.md`

## Why AIIR
- Scambio AI2AI sicuro con firma per nodo
- Trust esplicito peer-by-peer con revoca immediata
- Anti-replay e finestra temporale su pacchetti importati
- Runtime nativo C con policy deny-by-default
- Operativita' server-ready con smoke, backup e restore

## Quickstart
```bash
/var/www/aiir/server/scripts/lockdown-perms.sh
/var/www/aiir/ai/bootstrap.sh
/var/www/aiir/server/scripts/smoke-runtime.sh
```

## Security Baseline
- `AI_POLICY_ALLOW_DB_EXEC=0`
- `AI_POLICY_ALLOW_OPS=` (vuoto)
- peer trust/revoke: `trust-add-peer.run.sh` / `trust-revoke-peer.run.sh`
- anti-replay ledger: `ai/state/import-ledger.log`
- signed-time window:
  - `AIIR_SIGNED_AT_MAX_AGE_SEC`
  - `AIIR_SIGNED_AT_MAX_FUTURE_SEC`

## Discoverability
- `llms.txt` per indicizzazione AI-friendly
- `aiir.repo.json` come metadata machine-readable
