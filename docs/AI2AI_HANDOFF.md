# AI2AI Handoff

## Modello
AIIR usa trust esplicito tra nodi:
- ogni nodo ha `node.id` e coppia chiavi propria
- i peer fidati sono nel trust store
- i pacchetti devono essere firmati e verificati

## Setup nodo
```bash
/var/www/aiir/ai/exchange/bootstrap-node.run.sh
```

Output atteso:
- `ai/state/peer.mode` = `isolated` o `paired`
- onboarding bundle in `ai/state/onboarding/`

## Trust peer
```bash
/var/www/aiir/ai/exchange/trust-add-peer.run.sh <peer-id> <peer-pub.pem>
```

## Revoca peer
```bash
/var/www/aiir/ai/exchange/trust-revoke-peer.run.sh <peer-id>
```

## Build e apply sync
```bash
/var/www/aiir/ai/exchange/sync-core.run.sh build <src-dir> <pkg-dir> [core-dir]
/var/www/aiir/ai/exchange/sync-core.run.sh apply <pkg-dir> <out-dir>
```

## Controlli sicurezza import
- firma valida su payload firma
- signer non revocato
- anti-replay ledger
- finestra temporale `signed_at`

## Variabili chiave
- `AIIR_REQUIRE_SIGNED_PACKAGE`
- `AIIR_ALLOW_REPLAY`
- `AIIR_SIGNED_AT_MAX_AGE_SEC`
- `AIIR_SIGNED_AT_MAX_FUTURE_SEC`
