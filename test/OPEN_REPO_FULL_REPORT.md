# Open Repo Full Benchmark (AIIR MB + Parity)

Last run (UTC): `2026-03-06T09:15:23Z`

Base package overhead excluded from AIIR net size: 0.00 MB (2281 bytes)
Full analysis threshold (ingest+parity): 350 MB source size

| Repo | Commit | Original MB | AIIR Net MB | Reduction | Reuse | Logic | Visual | Overall | Note |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| `https://github.com/angular/angular.git` | `d69c468` | 159.59 | 42.21 | 73.55% | 100.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/ansible/ansible.git` | `0183e38` | 19.34 | 12.49 | 35.42% | 0.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/apache/spark.git` | `325763fe` | 233.74 | 29.08 | 87.56% | 100.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/django/django.git` | `23931eb` | 56.76 | 18.78 | 66.92% | 100.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/dotnet/runtime.git` | `8b63bd26` | 730.23 | 4.04 | 99.45% | 0% | 0% | 0% | 0% | analysis_skipped_large |
| `https://github.com/elastic/elasticsearch.git` | `f5c3e5f9` | 469.76 | 238.03 | 49.33% | 0% | 0% | 0% | 0% | analysis_skipped_large |
| `https://github.com/flutter/flutter.git` | `7a95d24e` | 176.38 | 5.74 | 96.75% | 100.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/golang/go.git` | `cbab448` | 171.07 | 61.75 | 63.91% | 100.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/hashicorp/terraform.git` | `02723fc` | 30.35 | 19.96 | 34.24% | 0.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/kubernetes/kubernetes.git` | `1f5701a4` | 287.60 | 131.41 | 54.31% | 100.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/laravel/framework.git` | `cf4df18` | 30.92 | 15.27 | 50.62% | 100.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/microsoft/vscode.git` | `e528731` | 171.31 | 88.59 | 48.29% | 100.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/nodejs/node.git` | `a06e7896` | 744.54 | 69.92 | 90.61% | 0% | 0% | 0% | 0% | analysis_skipped_large |
| `https://github.com/pytorch/pytorch.git` | `b7fad45` | 249.32 | 80.56 | 67.69% | 100.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/rails/rails.git` | `074429b` | 42.38 | 18.73 | 55.80% | 100.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/rust-lang/rust.git` | `69370dc4` | 247.76 | 112.90 | 54.43% | 100.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/tensorflow/tensorflow.git` | `c9a1ee99` | 473.39 | 49.12 | 89.62% | 0% | 0% | 0% | 0% | analysis_skipped_large |
| `https://github.com/torvalds/linux.git` | `5ee8dbf54` | 1781.20 | 44.89 | 97.48% | 0% | 0% | 0% | 0% | analysis_skipped_large |
| `https://github.com/vuejs/core.git` | `cea3cf7` | 7.52 | 4.33 | 42.38% | 100.00% | 100.00% | 100.00% | 100.00% | ok |
| `https://github.com/facebook/react.git` | `4610359` | 45.38 | 22.08 | 51.34% | 100.00% | 100.00% | 100.00% | 100.00% | ok |

Summary (latest per repo+commit): reduction_avg=65.48% overall_parity_avg_ok=100.00% ok=15/20 skipped_large=5
