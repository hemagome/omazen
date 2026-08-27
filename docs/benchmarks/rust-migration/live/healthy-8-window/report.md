# Omazen benchmark

Date: `2026-08-27T10:10:33-06:00`

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
| Sync duration | 200 | 4.164 | 5.072 | 5.216 | 6.298 | 7.453 | 7.934 |
| Trigger → PALETTE_APPLIED | 200 | 4.534 | 5.743 | 5.986 | 8.103 | 8.655 | 10.018 |
| Trigger → CHROME_CSS_APPLIED | 200 | 104.797 | 112.791 | 111.746 | 118.723 | 122.619 | 140.018 |
| PALETTE_APPLIED → CHROME_CSS_APPLIED | 200 | 100.000 | 106.500 | 105.760 | 113.000 | 117.020 | 130.000 |

### atomic

| Metric | N | Minimum (ms) | p50 (ms) | Mean (ms) | p95 (ms) | p99 (ms) | Maximum (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Trigger → PALETTE_APPLIED | 200 | 0.000 | 0.603 | 0.819 | 2.524 | 3.362 | 3.545 |
| Trigger → CHROME_CSS_APPLIED | 200 | 99.981 | 108.793 | 106.545 | 113.510 | 123.604 | 126.545 |
| PALETTE_APPLIED → CHROME_CSS_APPLIED | 200 | 100.000 | 108.000 | 105.730 | 113.000 | 121.010 | 123.000 |

## Files

- Complete data: `samples.csv`
- Observed bridge: `/home/hemagome/.local/state/omazen/bridge.log`
- Observed palette: `/home/hemagome/.local/state/omazen/palette.json`
