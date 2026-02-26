# AI2AI Handoff

## Model
AIIR uses explicit trust between nodes:
- each node has its own `node.id` and key pair
- trusted peers are stored in a trust store
- exchanged packages must be signed and verified

## Node Setup
```bash
/var/www/aiir/ai/exchange/bootstrap-node.run.sh
```

Expected output:
- `ai/state/peer.mode` is `isolated` or `paired`
- onboarding bundle in `ai/state/onboarding/`

## Trust a Peer
```bash
/var/www/aiir/ai/exchange/trust-add-peer.run.sh <peer-id> <peer-pub.pem>
```

## Revoke a Peer
```bash
/var/www/aiir/ai/exchange/trust-revoke-peer.run.sh <peer-id>
```

## Build and Apply Sync
```bash
/var/www/aiir/ai/exchange/sync-core.run.sh build <src-dir> <pkg-dir> [core-dir]
/var/www/aiir/ai/exchange/sync-core.run.sh apply <pkg-dir> <out-dir>
```

## Import Security Checks
- valid signature on signed payload
- signer not revoked
- anti-replay ledger check
- signed-time window validation (`signed_at`)

## Key Variables
- `AIIR_REQUIRE_SIGNED_PACKAGE`
- `AIIR_ALLOW_REPLAY`
- `AIIR_SIGNED_AT_MAX_AGE_SEC`
- `AIIR_SIGNED_AT_MAX_FUTURE_SEC`
