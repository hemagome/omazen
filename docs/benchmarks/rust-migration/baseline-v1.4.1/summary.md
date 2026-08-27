# Generated benchmark summary

This file is generated entirely from `latency.csv`, `cpu.csv`, and `memory.csv`. Failed samples and sampler warnings remain in the raw files.

Successful samples: 600/600. Sampler warnings: 0.

| Metric | N | Minimum | p50 | Mean | Std. dev. | p95 | p99 | Maximum | Unit |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Wall latency | 600 | 68.983 | 84.301 | 84.518 | 4.824 | 93.038 | 96.615 | 105.597 | ms |
| User CPU | 600 | 0.000 | 10.000 | 6.883 | 4.668 | 10.000 | 10.000 | 20.000 | ms |
| System CPU | 600 | 0.000 | 10.000 | 8.167 | 3.869 | 10.000 | 10.000 | 10.000 | ms |
| Process-tree RSS | 600 | 7.332 | 10.711 | 11.357 | 1.137 | 13.363 | 13.492 | 13.633 | MiB |
| Process-tree PSS | 600 | 1.170 | 1.695 | 1.710 | 0.188 | 2.130 | 2.272 | 2.363 | MiB |

Percentiles use linear interpolation at `(N - 1) × p`. No outlier is removed.
