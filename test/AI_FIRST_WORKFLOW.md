# AIIR Test Workflow (AI-first)

Goal:
- use open repositories to detect gaps and improve AIIR structure
- keep all test operations isolated under `/var/www/aiir/test`

Reusable commands:
- Run full benchmark list from file:
  - `/var/www/aiir/test/benchmark-open-repos-full.sh`
- Run full benchmark with explicit repositories:
  - `/var/www/aiir/test/benchmark-open-repos-full.sh <repo1.git> <repo2.git> ...`
- Run fixed canary regression pack:
  - `/var/www/aiir/server/scripts/aiir bench --regression-pack --gate-strict`
- Edit repository source list:
  - `/var/www/aiir/test/REPO_SOURCES.txt`
- Edit excluded feature keys for backlog prioritization:
  - `/var/www/aiir/test/FEATURE_EXCLUSIONS.txt`

Artifacts:
- CSV benchmark log:
  - `/var/www/aiir/test/OPEN_REPO_FULL_LOG.csv`
- Human-readable benchmark report:
  - `/var/www/aiir/test/OPEN_REPO_FULL_REPORT.md`
- Profiling report:
  - `/var/www/aiir/test/OPEN_REPO_FULL_PROFILE_REPORT.md`
- Feature matrix for gap analysis:
  - `/var/www/aiir/test/FEATURE_MATRIX.csv`
- Improvement backlog report:
  - `/var/www/aiir/test/AIIR_IMPROVEMENT_BACKLOG.md`
- Feature exclusions policy:
  - `/var/www/aiir/test/FEATURE_EXCLUSIONS.txt`

Measurement model:
- Original size: `du -sb` on shallow clone
- AIIR package size: `du -sb` on package built by `ai/exchange/build-package.run.sh`
- AIIR net size: AIIR package size minus base package overhead (empty-source package)

AI-first packaging defaults (toolchain):
- language-focused collection enabled (`AIIR_BUILD_LANG_ONLY=1`)
- text-only filtering enabled (`AIIR_BUILD_TEXT_ONLY=1`)
- likely-binary extensions skipped (`AIIR_BUILD_SKIP_BINARY_EXT=1`)
- per-file cap enabled (`AIIR_BUILD_MAX_FILE_BYTES=524288`)

Cleanup policy:
- temporary clones/packages/logs are removed after each run
- only scripts/list/csv/reports stay in `test`
