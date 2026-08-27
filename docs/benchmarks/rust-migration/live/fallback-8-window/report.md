# Omazen benchmark

Date: `2026-08-27T10:32:29-06:00`

This benchmark measures the currently installed bridge. Bridge event precision is limited to milliseconds because `bridge.log` records ISO timestamps with millisecond precision.

Watcher backend: `polling-fallback`

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
| Sync duration | 200 | 4.241 | 4.910 | 5.166 | 6.714 | 8.163 | 11.002 |
| Trigger → PALETTE_APPLIED | 200 | 5.875 | 140.597 | 138.831 | 243.097 | 249.942 | 254.221 |
| Trigger → CHROME_CSS_APPLIED | 200 | 107.394 | 264.502 | 245.091 | 348.321 | 360.475 | 366.221 |
| PALETTE_APPLIED → CHROME_CSS_APPLIED | 200 | 99.000 | 101.000 | 106.260 | 120.000 | 135.050 | 175.000 |

### atomic

| Metric | N | Minimum (ms) | p50 (ms) | Mean (ms) | p95 (ms) | p99 (ms) | Maximum (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Trigger → PALETTE_APPLIED | 200 | 0.319 | 219.033 | 176.689 | 239.390 | 245.816 | 249.621 |
| Trigger → CHROME_CSS_APPLIED | 200 | 100.319 | 322.465 | 281.014 | 343.709 | 353.627 | 357.793 |
| PALETTE_APPLIED → CHROME_CSS_APPLIED | 200 | 100.000 | 101.000 | 104.325 | 113.000 | 113.000 | 121.000 |

## Files

- Complete data: `samples.csv`
- Observed bridge: `/home/hemagome/.local/state/omazen/bridge.log`
- Observed palette: `/home/hemagome/.local/state/omazen/palette.json`
