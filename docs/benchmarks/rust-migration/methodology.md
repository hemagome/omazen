# Rust migration benchmark methodology

The migration keeps raw observations separate from generated summaries. A
result directory is valid only when it contains the environment manifest,
complete CSV samples, warnings and a summary reproducible with:

```bash
node tests/generate-benchmark-report.mjs RESULT_DIRECTORY
```

## CLI measurements

`tests/cli-benchmark.sh` creates an isolated state directory and runs the chosen
CLI against a fixed palette. It performs warmups, at least three independent
runs and a configurable number of measured iterations. The Linux process-tree
sampler records monotonic wall time, observed user/system CPU ticks, maximum
aggregate RSS/PSS, process count and sampling warnings. Processes that complete
too quickly for two samples remain explicit warnings rather than disappearing.

Use at least 100 samples per latency scenario and at least 200 when p99 decides
acceptance:

```bash
OMAZEN_IMPLEMENTATION=bash tests/cli-benchmark.sh \
  --runs 3 --iterations 200 --warmups 10 \
  --output-dir docs/benchmarks/rust-migration/baseline-v1.4.1
```

## Live bridge measurements

`tests/benchmark.sh` measures `sync` and identical atomic replacements against
the running bridge. Record the exact backend, window count, active theme, hook
order, timeout, warmups and run number. A valid campaign covers 1, 4 and 8
windows with healthy inotify, then repeats the relevant cases with forced
polling fallback. Bridge ISO timestamps have millisecond resolution; trigger
timestamps remain nanoseconds and must not be presented as equally precise.

Full theme-set measurements require two prequalified themes and must capture the
starting theme before the first run, alternate order, and restore that starting
theme after every run including failure. Live disable/enable follows the same
rule for the initial enabled state. These scenarios are never launched merely
because the repository benchmark is invoked.

## CPU and memory campaigns

Transient commands use the process-tree sampler. Persistent watcher and Zen
scenarios sample `/proc/<pid>/smaps_rollup` and CPU ticks at a fixed interval for
at least ten minutes. Capture 1, 4 and 8 windows, healthy inotify, forced
fallback, idle, a 100-change burst and post-burst recovery. Report Omazen and
`inotifywait` separately from the complete Zen tree as well as combined.

Every timeout, nonzero exit, missing PSS permission, log rotation, backend
change, sampler under-run and restore failure is part of the raw result. Do not
discard outliers. Rerun noisy scenarios as an additional run rather than
replacing the original data.

`tests/live-idle-sampler.sh` captures fixed-interval `/proc` observations for
an already prepared window/backend scenario. `tests/live-theme-benchmark.sh`
alternates a secondary theme with the captured original theme and restores the
original through an exit trap. Both require a real graphical session and are
therefore intentionally excluded from the automatic repository gate.
