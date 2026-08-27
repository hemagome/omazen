# Latency benchmark

`tests/benchmark.sh` measures the current implementation without changing the
polling interval or adding instrumentation to the bridge.

## Requirements

- Zen must be open with the Omazen bridge loaded.
- Omazen's `palette.json` and `bridge.log` must exist.
- The bridge must record both `PALETTE_APPLIED` and `CHROME_CSS_APPLIED`.
- For event-driven measurements, the current bridge session should also record
  `WATCHER_READY backend=inotify`; `WATCHER_FALLBACK` means the 250 ms fallback
  is active instead.

## Usage

To measure Omazen's sync path and isolate file-change detection:

```bash
tests/benchmark.sh --mode all --iterations 20 \
  --output-dir /tmp/omazen-benchmark-current
```

Available modes:

- `sync`: runs `bin/omazen sync`; includes palette generation, the atomic write
  of `palette.json`, and the bridge's subsequent detection. It does not include
  the complete staging process or the other hooks run by `omarchy theme set`.
- `atomic`: replaces `palette.json` with an identical copy using `mv`; measures
  the detection and application path after the atomic replacement.
- `all`: runs both modes.

The `atomic` mode changes only the file metadata and preserves its contents, so
it does not visibly change the active palette. Each run produces:

- `report.md`: summary with minimum, p50/median, mean, p95, p99, and maximum
  values.
- `samples.csv`: complete samples, including the number of windows that
  recorded each event.

## Metrics and percentiles

The benchmark reports p50/median, p95, and p99 in addition to the boundary and
average values:

- minimum: the fastest observed sample;
- p50/median: half of the samples are at or below this value;
- mean: the arithmetic average;
- p95: 95% of the measured samples completed at or below this latency; the
  slowest 5% were slower;
- p99: 99% of the measured samples completed at or below this latency; the
  slowest 1% were slower;
- maximum: the slowest observed sample.

Minimum and maximum are boundary values, not substitutes for p95 or p99.
Percentiles use linear interpolation between the ordered samples, using the
position `1 + (N - 1) * percentile`. This makes the calculation deterministic
for small sample sets as well as larger runs.

For a useful p95/p99 measurement, collect enough samples—at least 20 for a
rough p95 and preferably 100 or more for stable p95/p99 values. The raw
`samples.csv` remains available for independent recalculation without rerunning
the benchmark.

## Interpretation

`Trigger → PALETTE_APPLIED` represents the latency until the bridge finishes
validating and applying the palette. `Trigger → CHROME_CSS_APPLIED` also
includes confirmation of the computed CSS. In `sync` mode, the trigger is the
start of the command; in `atomic` mode, it is the `mv` that publishes the file.

The `atomic` mode is the direct comparison point for the old 250 ms polling
path and the event-driven watcher. A valid comparison must record the watcher
backend from `bridge.log` alongside the samples.

The bridge timestamps have millisecond resolution. To compare polling, `inotify`
or a direct hook, run at least 20 iterations per scenario and document the
number of windows, Zen version, active theme, system load, and active Omarchy
hooks.

This first version does not measure CPU/RAM usage for Zen or an alternative
watcher. Those measurements should be captured in a separate scenario so they
are not mixed with application latency.
