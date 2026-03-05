# AI2AI Migration Policy v1

## Scope
Policy for migrating existing projects into AIIR and propagating them across AI nodes.

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

## Out of Scope (v1)
- full plugin ecosystem parity for external framework plugins
- exact internal runtime emulation of non-AIIR frameworks
