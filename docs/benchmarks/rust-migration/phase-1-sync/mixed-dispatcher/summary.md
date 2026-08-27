# Generated benchmark summary

This file is generated entirely from `latency.csv`, `cpu.csv`, and `memory.csv`. Failed samples and sampler warnings remain in the raw files.

Successful samples: 600/600. Sampler warnings: 488.

| Metric | N | Minimum | p50 | Mean | Std. dev. | p95 | p99 | Maximum | Unit |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Wall latency | 600 | 12.053 | 15.909 | 15.940 | 1.366 | 18.219 | 19.658 | 20.833 | ms |
| User CPU | 600 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | ms |
| System CPU | 600 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 | ms |
| Process-tree RSS | 600 | 0.641 | 7.693 | 6.782 | 1.430 | 8.113 | 11.438 | 11.824 | MiB |
| Process-tree PSS | 585 | 0.152 | 0.511 | 0.621 | 0.202 | 1.002 | 1.084 | 1.237 | MiB |

Percentiles use linear interpolation at `(N - 1) × p`. No outlier is removed.
