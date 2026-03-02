# AIIR Improvement Backlog (AI-first)

Generated at (UTC): `2026-03-02T16:27:45Z`

Scope: compare AIIR (ai/server/docs) against features commonly found in sampled open repositories.

## Priority Candidates (missing in AIIR, common in repos)
| Feature | Repos with feature | AIIR has feature | Priority | Action |
|---|---:|---:|---|---|
| RBAC/permissions | 1/10 | 0 | medium | evaluate with targeted PoC and decide adoption |
| OpenTelemetry/tracing | 8/10 | 0 | high | design+implement in core/runtime/security and document in docs-tech |
| Structured logging | 6/10 | 0 | high | design+implement in core/runtime/security and document in docs-tech |
| Idempotency keys | 1/10 | 0 | medium | evaluate with targeted PoC and decide adoption |
| Retry/backoff policies | 3/10 | 0 | high | design+implement in core/runtime/security and document in docs-tech |
| API schema/OpenAPI | 3/10 | 0 | high | design+implement in core/runtime/security and document in docs-tech |
| Middleware/plugin extension | 5/10 | 0 | high | design+implement in core/runtime/security and document in docs-tech |

## Strengthen Existing Capabilities
| Feature | Repos with feature | AIIR has feature | Action |
|---|---:|---:|---|
| Metrics endpoint | 4/10 | 1 | tighten tests, docs, and defaults for production hardening |
| Fuzz/property testing | 4/10 | 1 | tighten tests, docs, and defaults for production hardening |

## Artifacts
- Feature matrix CSV: `/var/www/aiir/test/FEATURE_MATRIX.csv`
- Repo source list: `/var/www/aiir/test/REPO_SOURCES.txt`
- Feature exclusions: `/var/www/aiir/test/FEATURE_EXCLUSIONS.txt`
