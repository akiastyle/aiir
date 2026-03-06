# Open Repo Full Benchmark (AIIR MB + Parity)

Last run (UTC): `2026-03-06T11:39:53Z`

Base package overhead excluded from AIIR net size: 0.00 MB (2281 bytes)
Full analysis threshold (ingest+parity): 350 MB source size

| Repo | Commit | Original MB | AIIR Net MB | Reduction | Reuse | PAIIR | OAIIR | Logic | Visual | Overall | Chunk | Note |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| `https://github.com/actix/actix-web.git` | `3089b88` | 3.70 | 2.54 | 31.31% | 100.00% | 7 (1 custom) | 7 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/encode/starlette.git` | `a1fd9d8` | 6.17 | 0.60 | 90.21% | 100.00% | 8 (2 custom) | 8 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/expressjs/express.git` | `6c4249f` | 0.89 | 0.54 | 39.11% | 100.00% | 7 (1 custom) | 7 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/gin-gonic/gin.git` | `3e44fdc` | 1.14 | 0.67 | 41.57% | 100.00% | 7 (1 custom) | 7 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/go-chi/chi.git` | `a54874f` | 0.49 | 0.29 | 40.41% | 100.00% | 7 (1 custom) | 7 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/jqlang/jq.git` | `3cd7e0d` | 5.82 | 0.95 | 83.62% | 100.00% | 8 (2 custom) | 8 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/labstack/echo.git` | `1753170` | 1.85 | 1.05 | 43.45% | 100.00% | 7 (1 custom) | 7 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/pallets/flask.git` | `3a9d54f` | 2.53 | 0.59 | 76.64% | 100.00% | 8 (2 custom) | 8 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/psf/requests.git` | `0e4ae38` | 8.36 | 0.38 | 95.48% | 100.00% | 7 (1 custom) | 7 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/tiangolo/fastapi.git` | `627c10a` | 47.56 | 3.95 | 91.69% | 100.00% | 8 (2 custom) | 8 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/axios/axios.git` | `84285c8` | 2.19 | 0.66 | 69.72% | 100.00% | 8 (2 custom) | 8 (+0) | 100.00% | 100.00% | 100.00% | none | ok |

Summary (latest per repo+commit): reduction_avg=63.93% overall_parity_avg_effective=100.00% paiir_avg=7.45 oaiir_avg=7.45 oaiir_html_ops_avg=299.64 oaiir_css_ops_avg=50.64 oaiir_js_ops_avg=1424.00 ok=11/11 chunked=0 skipped_large=0
