# PAIIR -> OAIIR Future Workflow

Date: 2026-03-06
Scope: future evolution path for AIIR-native web execution

## Objective
Move from intermediate semantic representation (PAIIR) to executable native representation (OAIIR) with deterministic runtime behavior.

## Operating Loop (every repo batch)
1. Ingest repository and collect PAIIR/OAIIR metrics.
2. Extract uncovered semantic patterns from HTML/CSS/JS.
3. Propose new PAIIR primitives (if needed).
4. Lower PAIIR to OAIIR opcode candidates.
5. Validate on parity tests and regression suite.
6. Promote only opcodes/primitives that improve parity without regressions.
7. Update registry, catalogs, compiler stages, and benchmark reports.

## Near-Term Roadmap
1. Stabilize PAIIR taxonomy:
- split by domain: `dom`, `style`, `event`, `state`, `route`, `data`
- freeze naming/versioning rules.
2. Expand OAIIR registry:
- move provisional opcodes to stable with argument schemas
- add version field (`oaiir_web_v1`).
3. Improve compiler lowering:
- HTML: richer node/attr/event extraction
- CSS: selector/declaration normalization
- JS: function/call/event/state extraction with safer parsing.
4. Introduce OAIIR executor prototype:
- interpret opcode stream
- produce deterministic render output
- run event loop subset.
5. Add strict parity gate:
- block promotion when baseline parity drops
- track gain per promoted opcode.

## Metrics To Track
- `paiir_total`, `paiir_custom_total`
- `oaiir_total`, `oaiir_new_total`
- `oaiir_html_ops_total`, `oaiir_css_ops_total`, `oaiir_js_ops_total`
- parity metrics (`logic`, `visual`, `overall`)
- regression count per batch

## Promotion Criteria
- No regression on baseline benchmark set.
- Measurable parity gain or deterministic-runtime gain.
- Audit and verify pack must pass.

## Constraints
- AI-first: human artifacts are adapters, not runtime source of truth.
- Keep CLI surface minimal; grow internal capability.
- Preserve deterministic behavior and auditability.
