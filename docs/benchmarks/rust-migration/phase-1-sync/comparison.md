# Phase 1 `sync` comparison

The Bash baseline is commit `84d3fd1`; the Rust candidate and mixed dispatcher
are commit `24921b5`. Every latency set contains three runs of 200 measured
samples after ten warmups per run. All 1,800 commands succeeded and no outlier
was discarded.

| Implementation | p50 | p95 | p99 | Maximum | p50 change |
|---|---:|---:|---:|---:|---:|
| Bash v1.4.1 | 84.301 ms | 93.038 ms | 96.615 ms | 105.597 ms | baseline |
| Rust direct | 8.285 ms | 11.595 ms | 13.943 ms | 16.595 ms | -90.2% |
| Mixed pre-source dispatcher | 15.909 ms | 18.219 ms | 19.658 ms | 20.833 ms | -81.1% |

The mixed path exceeds the 30% p50 improvement target and improves both tails.
It preserves byte-identical JSON, private modes, same-directory atomic rename
and the `MOVED_TO` event in differential and explicit inotify tests.

CPU tick accounting has 10 ms kernel resolution, so the short Rust commands
round to zero and cannot support a precise CPU percentage claim. The sampler
also could not observe direct Rust RSS/PSS before process exit in any sample;
those 600 under-runs are retained as warnings. The longer mixed path yielded
observable RSS for all samples (p50 7.693 MiB versus Bash 10.711 MiB) and PSS
for 585/600 samples (p50 0.511 MiB versus Bash 1.695 MiB). These memory numbers
are encouraging but remain provisional until an external high-frequency or
cooperatively paused measurement qualifies the direct binary.

This campaign covers disposable `cli-sync` only. Event-to-apply latency,
healthy inotify and forced fallback, 1/4/8 live windows, idle CPU, leak sampling
and full theme restore are still required before switching the installed
default. Their absence does not invalidate CLI parity, but it prevents declaring
the complete Phase 1 integration gate finished.
