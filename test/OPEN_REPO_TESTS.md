# Open Repo Benchmarks (AIIR)

Last run (UTC): `2026-03-03T07:12:42Z`

Base package overhead excluded from AIIR net size: 0.00 MB (2329 bytes)

| Repo | Commit | Date (UTC) | Original MB | AIIR Net MB | Reduction | Note |
|---|---|---:|---:|---:|---:|---|
| `https://github.com/psf/requests.git` | `4bd79e3` | 2026-03-02T10:48:42Z | 8.36 | 4.97 | 40.58% | ok |
| `https://github.com/pallets/flask.git` | `c34d6e8` | 2026-03-02T10:48:42Z | 2.53 | 1.73 | 31.61% | ok |
| `https://github.com/jqlang/jq.git` | `c3d3e7d` | 2026-03-02T10:48:42Z | 5.82 | 2.32 | 60.21% | ok |
| `https://github.com/psf/requests.git` | `4bd79e3` | 2026-03-02T10:51:01Z | 8.36 | 4.97 | 40.58% | ok |
| `https://github.com/pallets/flask.git` | `c34d6e8` | 2026-03-02T10:51:01Z | 2.53 | 1.73 | 31.61% | ok |
| `https://github.com/jqlang/jq.git` | `c3d3e7d` | 2026-03-02T10:51:01Z | 5.82 | 2.32 | 60.21% | ok |
| `https://github.com/tiangolo/fastapi.git` | `ca5f60e` | 2026-03-02T10:51:01Z | 47.57 | 32.05 | 32.63% | ok |
| `https://github.com/expressjs/express.git` | `6c4249f` | 2026-03-02T10:51:01Z | 0.89 | 0.69 | 23.23% | ok |
| `https://github.com/gin-gonic/gin.git` | `cb2b764` | 2026-03-02T10:51:01Z | 1.14 | 0.88 | 22.72% | ok |
| `https://github.com/go-chi/chi.git` | `a54874f` | 2026-03-02T10:51:01Z | 0.48 | 0.34 | 29.13% | ok |
| `https://github.com/psf/requests.git` | `4bd79e3` | 2026-03-02T16:22:19Z | 8.36 | 4.97 | 40.58% | ok |
| `https://github.com/pallets/flask.git` | `c34d6e8` | 2026-03-02T16:22:19Z | 2.53 | 1.73 | 31.61% | ok |
| `https://github.com/jqlang/jq.git` | `0df54c8` | 2026-03-02T16:22:19Z | 5.82 | 2.32 | 60.21% | ok |
| `https://github.com/tiangolo/fastapi.git` | `ca5f60e` | 2026-03-02T16:22:19Z | 47.57 | 32.05 | 32.62% | ok |
| `https://github.com/expressjs/express.git` | `6c4249f` | 2026-03-02T16:22:19Z | 0.89 | 0.69 | 23.23% | ok |
| `https://github.com/gin-gonic/gin.git` | `cb2b764` | 2026-03-02T16:22:19Z | 1.14 | 0.88 | 22.60% | ok |
| `https://github.com/go-chi/chi.git` | `a54874f` | 2026-03-02T16:22:19Z | 0.48 | 0.34 | 29.13% | ok |
| `https://github.com/psf/requests.git` | `4bd79e3` | 2026-03-02T16:27:27Z | 8.36 | 4.97 | 40.58% | ok |
| `https://github.com/pallets/flask.git` | `c34d6e8` | 2026-03-02T16:27:27Z | 2.53 | 1.73 | 31.61% | ok |
| `https://github.com/jqlang/jq.git` | `0df54c8` | 2026-03-02T16:27:27Z | 5.82 | 2.32 | 60.21% | ok |
| `https://github.com/tiangolo/fastapi.git` | `ca5f60e` | 2026-03-02T16:27:27Z | 47.57 | 32.05 | 32.62% | ok |
| `https://github.com/expressjs/express.git` | `6c4249f` | 2026-03-02T16:27:27Z | 0.89 | 0.69 | 23.23% | ok |
| `https://github.com/gin-gonic/gin.git` | `cb2b764` | 2026-03-02T16:27:27Z | 1.14 | 0.88 | 22.62% | ok |
| `https://github.com/go-chi/chi.git` | `a54874f` | 2026-03-02T16:27:27Z | 0.48 | 0.34 | 29.15% | ok |
| `https://github.com/encode/starlette.git` | `c14d0f7` | 2026-03-02T16:27:27Z | 6.17 | 3.58 | 42.04% | ok |
| `https://github.com/labstack/echo.git` | `1753170` | 2026-03-02T16:27:27Z | 1.85 | 1.35 | 26.97% | ok |
| `https://github.com/actix/actix-web.git` | `3089b88` | 2026-03-02T16:27:27Z | 3.70 | 3.07 | 16.99% | ok |
| `https://github.com/expressjs/express.git` | `6c4249f` | 2026-03-03T07:12:42Z | 0.89 | 0.69 | 23.23% | ok |
| `https://github.com/fastapi/fastapi.git` | `b54aa52` | 2026-03-03T07:12:42Z | 47.58 | 32.05 | 32.62% | ok |
| `https://github.com/axios/axios.git` | `84285c8` | 2026-03-03T07:12:42Z | 2.19 | 1.72 | 21.68% | ok |

Notes:
- Download, conversion and logs are executed under `/var/www/aiir/test`.
- AIIR net size = total AIIR package size - base package overhead.
- Cleanup keeps only CSV/report/repo-list/scripts in `/var/www/aiir/test`; temporary repos/packages are removed.
