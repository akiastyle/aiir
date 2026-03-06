# AI2AI Migration Policy v1

## Scope
Policy for migrating existing projects into AIIR and propagating them across AI nodes.

## Primary Mode (AIIR-native)
- Primary mode is AIIR-native build/operation.
- Migration/conversion is a secondary ingestion path for human-origin projects.
- Human-origin source shape is never the runtime target; AIIR primitives are the target.

## Core Rule
- Mandatory 1:1 parity on:
  - functional logic (behavior, flows, business outcomes)
  - visual output (HTML/CSS aesthetics and layout)
- Non-mandatory 1:1 parity on:
  - source code structure or language-level implementation details

## AI-first Conversion Order
1. Reuse native AIIR commands/constructs first.
2. If a gap exists, create project-specific commands.
3. Decompose project-specific commands into reusable AIIR primitives when stable.

## Metrics Vocabulary
- `PAIIR` (Primitive AIIR): semantic intermediate primitives used during ingest/migration.
- `OAIIR` (Opcode AIIR): numeric native execution units for runtime engine.
- Current state:
  - PAIIR metrics are tracked in ingest and benchmark outputs.
  - OAIIR metrics are tracked from registry-backed opcode emission:
    - `/var/www/aiir/docs/OAIIR_WEB_OPCODE_REGISTRY_V0.csv`

## Migration Pipeline
1. Ingest source project.
2. Normalize into AIIR migration contract.
3. Convert pages/scripts/API/DB into AIIR-operable assets.
4. Run parity checks:
   - logic parity
   - visual parity
5. Apply iterative AI auto-fixes until parity target is reached.
6. Sign/package and propagate AI2AI.

## Parity Targets
- logic parity target: 100% required for release candidate
- visual parity target: 100% required for release candidate
- temporary internal threshold during iteration can be lower, but publish requires full parity

## Decision Criteria
- Prefer simpler, deterministic transformations over opaque complex rewrites.
- Validate by outcome diff, not source-code similarity.
- Record every conversion decision in machine-readable reports.
- Do not require mTLS as a baseline dependency for runtime interoperability.
- Prefer AIIR capability-based auth flow over generic JWT session coupling for core ops.

## Out of Scope (v1)
- full plugin ecosystem parity for external framework plugins
- exact internal runtime emulation of non-AIIR frameworks
