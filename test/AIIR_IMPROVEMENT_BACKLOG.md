# AIIR Improvement Backlog (AI-first)

Generated at (UTC): `2026-03-02T16:23:20Z`

Scope: compare AIIR (ai/server/docs) against features commonly found in sampled open repositories.

## Priority Candidates (missing in AIIR, common in repos)
| Feature | Repos with feature | AIIR has feature | Priority | Action |
|---|---:|---:|---|---|
| OpenTelemetry/tracing | 5/7 | 0 | high | design+implement in core/runtime/security and document in docs-tech |
| Metrics endpoint | 2/7 | 0 | high | design+implement in core/runtime/security and document in docs-tech |
| Structured logging | 5/7 | 0 | high | design+implement in core/runtime/security and document in docs-tech |
| Idempotency keys | 1/7 | 0 | medium | evaluate with targeted PoC and decide adoption |
| Retry/backoff policies | 3/7 | 0 | high | design+implement in core/runtime/security and document in docs-tech |
| API schema/OpenAPI | 1/7 | 0 | medium | evaluate with targeted PoC and decide adoption |
| Middleware/plugin extension | 3/7 | 0 | high | design+implement in core/runtime/security and document in docs-tech |

## Strengthen Existing Capabilities
| Feature | Repos with feature | AIIR has feature | Action |
|---|---:|---:|---|
| Fuzz/property testing | 3/7 | 1 | tighten tests, docs, and defaults for production hardening |

## Artifacts
- Feature matrix CSV: `/var/www/aiir/test/FEATURE_MATRIX.csv`
- Repo source list: `/var/www/aiir/test/REPO_SOURCES.txt`
- Feature exclusions: `/var/www/aiir/test/FEATURE_EXCLUSIONS.txt`
