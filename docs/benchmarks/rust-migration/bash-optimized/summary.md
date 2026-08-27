# Generated benchmark summary

This file is generated entirely from `latency.csv`, `cpu.csv`, and `memory.csv`. Failed samples and sampler warnings remain in the raw files.

Successful samples: 600/600. Sampler warnings: 5.

| Metric | N | Minimum | p50 | Mean | Std. dev. | p95 | p99 | Maximum | Unit |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Wall latency | 600 | 8.590 | 9.546 | 9.913 | 1.078 | 12.265 | 13.406 | 14.793 | ms |
| User CPU | 600 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | ms |
| System CPU | 600 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | ms |
| Process-tree RSS | 600 | 5.707 | 9.373 | 8.831 | 1.783 | 11.649 | 11.762 | 11.957 | MiB |
| Process-tree PSS | 600 | 0.625 | 1.007 | 1.038 | 0.161 | 1.314 | 1.408 | 1.536 | MiB |

Percentiles use linear interpolation at `(N - 1) × p`. No outlier is removed.
