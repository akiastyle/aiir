# Open Repo Full Benchmark (AIIR MB + Parity)

Last run (UTC): `2026-03-08T12:13:03Z`

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
| `https://github.com/hapijs/hapi.git` | `f2a24f6` | 2.06 | 1.11 | 45.89% | 100.00% | 7 (1 custom) | 7 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/koajs/koa.git` | `d3ea8bf` | 0.85 | 0.39 | 54.76% | 100.00% | 7 (1 custom) | 7 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/lodash/lodash.git` | `0783181` | 5.21 | 0.42 | 91.96% | 100.00% | 7 (1 custom) | 7 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/moment/moment.git` | `18aba13` | 14.15 | 5.45 | 61.51% | 100.00% | 7 (1 custom) | 7 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/preactjs/preact.git` | `2459326` | 2.27 | 1.75 | 22.97% | 100.00% | 8 (2 custom) | 8 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/prisma/prisma.git` | `9fa295d` | 55.88 | 9.37 | 83.24% | 100.00% | 11 (5 custom) | 11 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/reduxjs/redux.git` | `ab47d94` | 46.96 | 0.75 | 98.40% | 100.00% | 9 (3 custom) | 9 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/sequelize/sequelize.git` | `c234325` | 11.59 | 5.56 | 52.03% | 100.00% | 10 (4 custom) | 10 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/solidjs/solid.git` | `a0524c0` | 1.91 | 0.85 | 55.48% | 100.00% | 8 (2 custom) | 8 (+0) | 100.00% | 100.00% | 100.00% | none | ok |
| `https://github.com/tailwindlabs/tailwindcss.git` | `bf2e2fe` | 6.03 | 3.50 | 42.00% | 100.00% | 8 (2 custom) | 8 (+0) | 100.00% | 100.00% | 100.00% | none | ok |

Summary (latest per repo+commit): reduction_avg=62.45% overall_parity_avg_effective=100.00% paiir_avg=7.81 oaiir_avg=7.81 oaiir_html_ops_avg=295.00 oaiir_css_ops_avg=174.38 oaiir_js_ops_avg=3401.57 ok=21/21 chunked=0 skipped_large=0
