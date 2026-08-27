# Generated benchmark summary

This file is generated entirely from `latency.csv`, `cpu.csv`, and `memory.csv`. Failed samples and sampler warnings remain in the raw files.

Successful samples: 600/600. Sampler warnings: 197.

| Metric | N | Minimum | p50 | Mean | Std. dev. | p95 | p99 | Maximum | Unit |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Wall latency | 600 | 4.031 | 4.414 | 4.524 | 0.371 | 5.327 | 5.791 | 6.254 | ms |
| User CPU | 600 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | ms |
| System CPU | 600 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | ms |
| Process-tree RSS | 600 | 5.563 | 5.734 | 6.848 | 1.944 | 11.633 | 11.762 | 11.922 | MiB |
| Process-tree PSS | 595 | 0.465 | 0.688 | 0.751 | 0.155 | 1.069 | 1.205 | 1.296 | MiB |

Percentiles use linear interpolation at `(N - 1) × p`. No outlier is removed.
