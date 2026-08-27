# Omazen benchmark

Date: `2026-08-27T09:25:59-06:00`

This benchmark measures the currently installed bridge. Bridge event precision is limited to milliseconds because `bridge.log` records ISO timestamps with millisecond precision.

Watcher backend: `inotify`

## Methodology

- `sync`: measures from the start of `bin/omazen sync` to `PALETTE_APPLIED` and `CHROME_CSS_APPLIED`; it does not include the complete `omarchy theme set` staging process.
- `atomic`: replaces `palette.json` with an identical copy using `mv` and measures from the replacement to both events. It does not change the visible colors.
- `palette → CSS`: measures the difference between `PALETTE_APPLIED` and `CHROME_CSS_APPLIED`.
- Each sample waits for both events before continuing; events from all windows are counted in `samples.csv`.

- The benchmark waits `1s` after the first CSS event to collect events from other windows.

## Results

### sync

| Metric | N | Minimum (ms) | p50 (ms) | Mean (ms) | p95 (ms) | p99 (ms) | Maximum (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Sync duration | 200 | 4.329 | 5.085 | 5.288 | 6.699 | 7.428 | 9.541 |
| Trigger → PALETTE_APPLIED | 200 | 4.193 | 5.481 | 5.732 | 7.098 | 8.145 | 17.210 |
| Trigger → CHROME_CSS_APPLIED | 200 | 104.664 | 105.879 | 106.137 | 107.804 | 110.995 | 117.210 |
| PALETTE_APPLIED → CHROME_CSS_APPLIED | 200 | 100.000 | 100.000 | 100.405 | 101.000 | 103.010 | 106.000 |

### atomic

| Metric | N | Minimum (ms) | p50 (ms) | Mean (ms) | p95 (ms) | p99 (ms) | Maximum (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Trigger → PALETTE_APPLIED | 200 | 0.000 | 0.249 | 0.386 | 1.419 | 1.787 | 1.984 |
| Trigger → CHROME_CSS_APPLIED | 200 | 99.703 | 100.712 | 100.767 | 101.824 | 102.132 | 102.762 |
| PALETTE_APPLIED → CHROME_CSS_APPLIED | 200 | 100.000 | 100.000 | 100.465 | 101.000 | 102.000 | 102.000 |

## Files

- Complete data: `samples.csv`
- Observed bridge: `/home/hemagome/.local/state/omazen/bridge.log`
- Observed palette: `/home/hemagome/.local/state/omazen/palette.json`
