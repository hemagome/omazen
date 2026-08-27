# Bash versus Rust migration comparison

All supported CLI commands have native Rust implementations: `setup`, `sync`,
`set`, `status`, `doctor`, `disable`, `enable`, `uninstall` and `help`. The
installed shell entry point immediately uses `exec` to enter the bundled binary
and retains the Bash implementation as a rollback fallback.

## Disposable `sync` results

Each result contains three runs of 200 measured samples after ten warmups. All
1,200 Bash/final-Rust samples succeeded; no timeout or outlier was removed.

| Implementation | p50 | p95 | p99 | Maximum | p50 change |
|---|---:|---:|---:|---:|---:|
| Bash v1.4.1 (`84d3fd1`) | 84.301 ms | 93.038 ms | 96.615 ms | 105.597 ms | baseline |
| Final Rust dispatcher (`5101fc7`) | 15.938 ms | 18.169 ms | 19.932 ms | 21.172 ms | -81.1% |

The candidate clears the 30% p50 requirement and improves p95/p99. Differential
tests preserve canonical bytes, modes, error output and atomic `MOVED_TO`.

The Bash sampler observed p50 RSS 10.711 MiB and PSS 1.695 MiB. The final mixed
path observed p50 RSS 7.678 MiB for 600 samples and p50 PSS 0.520 MiB for 587
samples. Because 490 short-process observations carry a `/proc` under-run
warning and CPU ticks have only 10 ms resolution, memory and CPU conclusions
remain provisional rather than silently treating missing observations as zero.

The release binary is 786,184 bytes before stripping and 626,712 bytes after
`strip`. It dynamically links only the system C runtime and `libgcc_s`. The one
direct dependency is `sha2`; all locked transitive licenses are recorded in
`docs/rust-dependencies.md`.

## Correctness gates

- Five differential `sync` fixture families pass.
- Thirteen read-only/diagnostic parity families pass, including JSON, stale
  palette, disabled state and current bridge errors.
- Eight state-changing parity families pass, including failed enable rollback
  and quoted theme names.
- The complete 12-family disposable lifecycle suite passes through Rust,
  including v1.4.0 stylesheet cleanup, known historical preference adoption,
  unknown-file refusal, symlink diagnostics, partial repair, failed staged
  update, backup and uninstall.

## Integration work still requiring a live session

The repository and disposable gates do not manufacture 1, 4 and 8 interactive
Zen windows or change the user's visible theme. Before release, run the live
campaign for healthy inotify and forced polling fallback, ten-minute idle/leak
sampling, burst behavior, disable/enable, full theme changes with restoration,
and event-to-apply latency. Until those results exist, the CLI migration is
qualified in disposable environments but the live release gate remains open.
