# Omazen benchmark

Date: `2026-08-27T09:49:24-06:00`

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
| Sync duration | 200 | 4.432 | 5.105 | 5.223 | 6.092 | 7.219 | 7.576 |
| Trigger → PALETTE_APPLIED | 200 | 4.534 | 5.659 | 5.816 | 7.396 | 7.914 | 9.278 |
| Trigger → CHROME_CSS_APPLIED | 200 | 104.729 | 111.195 | 110.496 | 117.752 | 118.827 | 120.279 |
| PALETTE_APPLIED → CHROME_CSS_APPLIED | 200 | 100.000 | 106.000 | 104.680 | 111.000 | 112.000 | 112.000 |

### atomic

| Metric | N | Minimum (ms) | p50 (ms) | Mean (ms) | p95 (ms) | p99 (ms) | Maximum (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Trigger → PALETTE_APPLIED | 200 | 0.000 | 0.422 | 0.518 | 2.124 | 2.602 | 2.624 |
| Trigger → CHROME_CSS_APPLIED | 200 | 99.894 | 105.678 | 104.969 | 111.626 | 113.132 | 113.513 |
| PALETTE_APPLIED → CHROME_CSS_APPLIED | 200 | 100.000 | 105.000 | 104.480 | 111.000 | 111.010 | 112.000 |

## Files

- Complete data: `samples.csv`
- Observed bridge: `/home/hemagome/.local/state/omazen/bridge.log`
- Observed palette: `/home/hemagome/.local/state/omazen/palette.json`
