# AIIR Web Native - Operation Plan

Date: 2026-03-06
Mode: AI-first, runtime-native, no human-first adapters

## Goal
Use every open-repo analysis cycle to increment the native AIIR web semantic engine.

## Always-On Loop (per repo batch)
1. Ingest repository with current stable pipeline.
2. Extract semantic web patterns (HTML/CSS/JS + routing + events + state markers).
3. Classify patterns:
- already covered by native AIIR primitives
- missing (candidate new primitive/opcode)
4. Generate candidate AIIR primitive/opcode proposals with:
- semantic name
- numeric id placeholder
- required args schema
- deterministic render/runtime behavior
5. Validate proposals on sampled files from the same repo batch.
6. Promote only if:
- parity tests improve
- no regression on existing benchmark set
- runtime behavior stays deterministic
7. Update:
- primitive registry (AIIR-native)
- test fixtures
- benchmark/parity reports

## Immediate Technical Backlog
1. Add `web-semantic-extract` stage after `ingest`.
2. Introduce `aiir-web-opcode-registry` with stable numeric ids.
Status: v0 active at `/var/www/aiir/docs/OAIIR_WEB_OPCODE_REGISTRY_V0.csv`.
3. Add `propose -> validate -> promote` automation in benchmark full flow.
4. Add regression gate:
- block promotion if parity on baseline repos drops.
5. Emit machine-readable delta report per batch:
- new patterns found
- promoted opcodes
- parity impact

## Constraints
- JSON is adapter only; internal source of truth must be AIIR-native representation.
- Keep CLI surface minimal; prefer internal capability growth over command sprawl.
- No mTLS dependency in baseline.
- Keep runtime deterministic and auditable.

## Done Criteria (phase gate)
- New repo batch yields either:
  - zero new patterns, or
  - promoted opcodes with measurable parity gain and no regressions.
