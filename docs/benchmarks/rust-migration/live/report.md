# Live Rust migration gate

Date: 2026-08-27. Result: **pass** for the requested live gate.

The working-tree Rust release was installed through the reversible staged
installer before testing. The installed binary SHA-256 was
`e2e74bf71d0eb18a7ac15017a81a400e69d300def519b0b3d55245e63774aed8`,
identical to `target/release/omazen-rust`. The campaign used Omazen 1.4.1,
Zen 1.21.15b, Omarchy 4.0.1, Hyprland 0.56.2, Linux 7.1.9, glibc 2.44,
inotify-tools 4.25.9.0 and the `powersave` CPU governor.

The original state was Osaka Jade with no Zen windows. The final state was
verified as Osaka Jade with no Zen windows or Omazen watcher process.

## Healthy inotify latency

Each window-count scenario contains 200 full `sync` samples and 200 identical
atomic replacements. No timeout or outlier was removed. Every one of the 1,200
samples produced exactly the expected number of palette and CSS events: 1, 4,
or 8 respectively. All windows shared one `inotifywait` process.

| Windows | `sync` p50 | sync → palette p50 / p95 / p99 | atomic → palette p50 / p95 / p99 |
|---:|---:|---:|---:|
| 1 | 5.085 ms | 5.481 / 7.098 / 8.145 ms | 0.249 / 1.419 / 1.787 ms |
| 4 | 5.105 ms | 5.659 / 7.396 / 7.914 ms | 0.422 / 2.124 / 2.602 ms |
| 8 | 5.072 ms | 5.743 / 8.103 / 8.655 ms | 0.603 / 2.524 / 3.362 ms |

The CLI duration did not grow with the number of windows. The event-to-first
palette p50 increased by only 0.262 ms from one to eight windows.

## Forced polling fallback

Only the Omazen-owned `inotifywait` child was sent `SIGTERM`; `/usr/bin` and
other system watchers were not modified. All eight windows logged
`WATCHER_FALLBACK` and continued through the 250 ms polling path. The scenario
again contains 200 `sync` and 200 atomic samples, with 400/400 successful and
exactly eight palette/CSS events per sample.

| Mode | Trigger → palette p50 | p95 | p99 | Maximum |
|---|---:|---:|---:|---:|
| `sync` | 140.597 ms | 243.097 ms | 249.942 ms | 254.221 ms |
| atomic | 219.033 ms | 239.390 ms | 245.816 ms | 249.621 ms |

The maximum 254.221 ms `sync` observation reflects scheduling around the
nominal 250 ms interval and remained far below the five-second timeout. Closing
Zen normally and reopening it restored `WATCHER_READY backend=inotify`.

## Ten-minute idle samples

Each scenario contains 121 fixed-interval observations over 600 seconds. RSS,
PSS, CPU ticks, context switches, process count, backend and window count are
retained in the corresponding `samples.csv`.

| Backend / windows | Zen processes | PSS start → end | Delta | Aggregate Zen CPU | Watcher |
|---|---:|---:|---:|---:|---|
| inotify / 1 | 12 | 661.122 → 664.215 MiB | +3.093 MiB | 0.280% | 1 process, ~0.35 MiB PSS, 0 measured ticks |
| inotify / 4 | 18 | 874.656 → 830.285 MiB | -44.371 MiB | 0.455% | 1 process, ~0.35 MiB PSS, 0 measured ticks |
| inotify / 8 | 18 | 930.328 → 922.729 MiB | -7.599 MiB | 0.373% | 1 process, ~0.35 MiB PSS, 0 measured ticks |
| fallback / 8 | 18 | 936.423 → 886.567 MiB | -49.855 MiB | 0.553% | no watcher process |

No scenario showed monotonic memory growth. The one-window sample ended 3.093
MiB higher but contained 19 downward intervals. The fallback sample rose to a
969.084 MiB peak, then garbage collection reduced it to 886.567 MiB by the end.
Polling added about 0.18 aggregate Zen CPU percentage points versus the healthy
eight-window sample.

## Full theme changes and restoration

Three complete Osaka Jade ↔ Catppuccin Latte cycles ran through
`omarchy theme set`, including all installed hooks. Six of six changes verified
the requested current theme and produced exactly two palette and CSS events,
one per open Zen window.

| Metric | Minimum | p50 | p95 | Maximum |
|---|---:|---:|---:|---:|
| Complete theme command | 689.679 ms | 730.218 ms | 826.856 ms | 843.074 ms |
| Start → palette | 616.535 ms | 654.338 ms | 672.846 ms | 673.655 ms |
| Start → CSS probe | 716.535 ms | 762.511 ms | 778.758 ms | 779.654 ms |

Osaka Jade was restored after every complete cycle and verified again during
final cleanup.

## Retained partial attempts

- `healthy-1-window/` contains 101 successful `sync` samples from the first
  attempt, which stopped when the old harness detected normal log rotation.
- `idle-healthy-1-window/` contains the initial partial idle run, stopped after
  the backend label became `unknown` once old `WATCHER_READY` lines aged out.

Both attempts remain intact. The reruns use a rotation-aware log cursor and a
process-based secondary backend check; no failed or noisy sample was silently
replaced.
