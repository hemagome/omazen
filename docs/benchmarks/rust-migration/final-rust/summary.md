# Generated benchmark summary

This file is generated entirely from `latency.csv`, `cpu.csv`, and `memory.csv`. Failed samples and sampler warnings remain in the raw files.

Successful samples: 600/600. Sampler warnings: 490.

| Metric | N | Minimum | p50 | Mean | Std. dev. | p95 | p99 | Maximum | Unit |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Wall latency | 600 | 12.370 | 15.938 | 15.918 | 1.396 | 18.169 | 19.932 | 21.172 | ms |
| User CPU | 600 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | ms |
| System CPU | 600 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | ms |
| Process-tree RSS | 600 | 0.508 | 7.678 | 6.773 | 1.361 | 8.126 | 9.320 | 11.742 | MiB |
| Process-tree PSS | 587 | 0.128 | 0.520 | 0.637 | 0.200 | 1.002 | 1.037 | 1.172 | MiB |

Percentiles use linear interpolation at `(N - 1) × p`. No outlier is removed.
