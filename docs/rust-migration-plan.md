# Rust migration plan

This document defines an incremental migration of Omazen's command-line runtime
from Bash to Rust 1.98.0. It deliberately keeps the Gecko integration in
JavaScript, the browser styling in CSS, and the Omarchy `theme-set` entry point
as a minimal shell hook.

The migration is evidence-driven. No Bash command may be replaced until its
current behavior and resource profile have been captured, its compatibility
contract has executable parity tests, and the Rust candidate has been measured
under the same conditions.

## Goals

- Replace `bin/omazen` and the appropriate `lib/*.sh` functionality with one
  compiled `omazen` CLI without a flag day.
- Pin the compiler and Cargo toolchain to Rust `1.98.0`.
- Preserve every supported command, file format, security boundary, exit code,
  environment override, provider mode, ownership rule and rollback guarantee.
- Quantify latency, CPU usage and memory usage before and after migration.
- Accept a migrated phase only when correctness is equivalent and measurements
  show an improvement or no material regression.
- Keep rollback possible after every phase.

## Non-goals

- Do not rewrite `zen/omazen-bridge.uc.js`, WindowActors, shared palette code or
  CSS in Rust. They call privileged Gecko APIs and must remain JavaScript/CSS.
- Do not introduce Rust-to-Gecko FFI, a native Gecko component, a local server
  or a page-visible API.
- Do not replace the healthy `inotifywait` watcher during the initial CLI
  migration. Its event-to-application latency is already approximately 1–2 ms.
- Do not create a persistent Rust daemon merely to claim a language migration.
- Do not change the normalized palette schema or broaden supported platforms.
- Do not publish a release or merge the branch as part of the migration unless
  separately requested after local qualification.

## Current architecture to document before implementation

The baseline documentation must describe the implementation at `v1.4.0`, not
an intended future design.

```text
omarchy theme set
  -> Omarchy runs theme-set hooks sequentially
  -> hooks/theme-set executes omazen sync
  -> Bash parses the active colors.toml subset
  -> Bash writes a same-directory temporary palette.json
  -> chmod 0600 + atomic rename to palette.json
  -> one process-wide inotifywait subprocess observes the state directory
  -> each subscribed Zen bridge schedules immediate sync
  -> JavaScript validates the trust boundary again
  -> chrome variables, content sheet, preferences and WindowActors update
  -> 5 s safety poll while inotify is healthy
  -> 250 ms polling fallback if the watcher cannot start or exits
```

Document all of the following in a dedicated current-runtime reference:

- Commands: `setup`, `sync`, `set`, `status`, `doctor`, `disable`, `enable`,
  `uninstall` and `help`.
- Inputs and precedence: explicit environment, persisted `active-colors` and
  `provider-mode`, XDG defaults and Omarchy defaults.
- The exact semantics of `OMAZEN_SKIP_THEME_HOOK=1`: skip only hook
  installation; retain sync, watcher, loader, diagnostics and ownership.
- The accepted `colors.toml` subset and canonical `palette.json` bytes.
- State paths, file modes, atomic rename, disabled marker and bounded logs.
- Zen profile discovery and supported installation checks.
- Owned-file manifests, known historical adoption, backups, update failure
  recovery, unknown-file refusal and uninstall behavior.
- The fixed `/usr/bin/inotifywait` command, watched leaves/events, one-process
  multi-window lifecycle, 5-second safety poll and 250 ms fallback.
- The security boundary: Rust may produce a palette, but JavaScript must still
  size-limit and strictly validate it before applying privileged state.
- Which latency markers represent actual work and which are diagnostics.
  `CHROME_CSS_APPLIED` is a delayed computed-style probe and is not the moment
  at which CSS was first applied.

The reference should link to the implementation and be updated whenever parity
work reveals undocumented behavior.

## Stable interoperability boundaries

Use processes and files, not FFI:

```text
Shell hook -> exec Rust CLI -> atomic palette.json -> inotify -> JavaScript
```

During migration, a small dispatcher may execute Rust for migrated commands and
retain Bash for the remainder. Dispatch to Rust before sourcing unrelated Bash
modules and use `exec` so the shell does not remain resident.

The following are compatibility contracts:

1. Command arguments and accepted arity.
2. Exit status for successful, invalid, unsupported and partially failed work.
3. stdout for normal results and stderr for warnings/errors.
4. Environment-variable precedence and persisted provider configuration.
5. Exact normalized JSON content, trailing newline and maximum size.
6. Same-directory temporary creation, mode `0600` and atomic replacement.
7. Directory mode `0700` and state-file ownership.
8. The inotify event pattern consumed by the bridge, especially `MOVED_TO`.
9. Manifest format, hash semantics, backup paths and safe uninstall.
10. Refusal to follow unsafe ownership assumptions or overwrite unknown files.
11. Behavior with spaces, symlinks, relative profiles and malformed input.
12. `doctor --json` schema and human-readable diagnostic meaning.

## Toolchain and workspace

Rust 1.98.0 is a stable release dated 2026-08-20; use the
[official release announcement](https://blog.rust-lang.org/releases/1.98.0/)
and [release notes](https://doc.rust-lang.org/stable/releases.html#version-1980-2026-08-20)
as the version references.

Add and commit:

- `rust-toolchain.toml` with channel `1.98.0`, minimal profile, and `rustfmt`
  plus `clippy` components.
- A Cargo workspace and committed `Cargo.lock`.
- `rust-version = "1.98"` and Rust 2024 edition in package metadata.
- CI checks that print `rustc -vV` and reject a compiler other than 1.98.0.
- `cargo fmt --check`, `cargo clippy --locked --all-targets -- -D warnings`,
  `cargo test --locked` and `cargo build --release --locked` gates.

Keep dependencies minimal. Every dependency must have a concrete purpose and a
license compatible with GPL-3.0-only. Prefer the standard library for process,
path and atomic filesystem work. Likely justified crates include a CLI parser,
Serde for structured output, a TOML parser if it can enforce Omazen's narrow
contract, SHA-256 and carefully reviewed Unix filesystem helpers. Do not let a
general TOML/JSON library silently broaden the accepted provider contract.

The developer machine did not have `cargo` or `rustc` when this plan was
written. Record the installation method and exact `rustc -vV` output in the
baseline report. The toolchain is a build dependency, not a runtime dependency
for users.

## Measurement campaign

### Principles

- Capture the complete Bash baseline before adding Rust implementation code.
- Use the same machine, Zen version, themes, window counts, power source,
  compositor session and background-load policy for before/after runs.
- Record raw samples; generated summaries are not a substitute for raw data.
- Use monotonic clocks for durations. Bridge ISO timestamps have millisecond
  resolution and must be labeled accordingly.
- Warm-up iterations are excluded and documented.
- Run at least 100 measured iterations per latency scenario; use 200 or more
  when p99 is a release criterion.
- Repeat each scenario at least three times and report run-to-run variation.
- Alternate candidate order where possible to reduce thermal/time bias.
- Restore the original theme and enabled state after every benchmark run.
- Never compare a healthy inotify run against a polling-fallback run without
  labeling them as different scenarios.

### Environment manifest

Every result set must include:

- Git commit and implementation (`bash`, `mixed`, or `rust`).
- Rust/Cargo versions and release-build profile when applicable.
- Omarchy, Zen, kernel, glibc, inotify-tools and compositor versions.
- CPU model, logical CPU count, RAM, architecture and filesystem type.
- Power source, CPU governor, system load and whether the machine was idle.
- Active theme, all installed `theme-set` hooks and their lexicographic order.
- Zen window count and process count.
- Watcher backend from `bridge.log`.
- Benchmark commands, iteration counts, warmups and timeout settings.

### Latency scenarios

Extend the benchmark tooling rather than collecting ad-hoc terminal numbers.
Store nanosecond trigger timestamps and bridge timestamps separately.

1. `cli-sync`: process start through successful `omazen sync` exit.
2. `atomic`: atomic replacement through `WATCHER_EVENT` and
   `PALETTE_APPLIED`.
3. `sync-to-apply`: process start through `PALETTE_APPLIED`.
4. `palette-to-css-probe`: `PALETTE_APPLIED` through the delayed
   `CHROME_CSS_APPLIED` diagnostic; label this as diagnostic latency.
5. `disable` and `enable`: command start through `DISABLED` or palette apply.
6. `full-theme-set`: `omarchy theme set` start through palette apply using two
   known-safe themes, including all Omarchy hooks. Restore the starting theme.
7. Startup: bridge load through watcher readiness and initial palette apply.
8. Multi-window: repeat atomic and sync scenarios with 1, 4 and 8 Zen windows.
9. Fallback: repeat the relevant scenarios with inotify deliberately
   unavailable so the 250 ms behavior remains qualified.

Report minimum, p50, mean, standard deviation, p95, p99 and maximum. Include
timeouts/failures as failures, never silently discard them.

### CPU scenarios

Measure process-tree CPU, not only the parent process:

1. CLI cold and warm `sync`, 100+ iterations.
2. A burst of 100 atomic replacements.
3. A burst of 100 full `sync` executions.
4. Ten minutes idle with 1, 4 and 8 Zen windows and healthy inotify.
5. Ten minutes idle with forced polling fallback.
6. Full theme changes between two fixed themes.

Capture user time, system time, wall time, context switches, process launches
and aggregate CPU percentage. Prefer `/proc`-based collection implemented in
the benchmark harness; use `perf stat` or `pidstat` only when availability and
permissions are recorded. Separate Omazen/inotify costs from the full Zen
process tree and also report the combined user-visible pipeline.

### Memory scenarios

For transient commands, measure peak resident memory for the entire process
tree, not only Bash or the Rust parent. For persistent processes, sample at a
fixed interval and report RSS and proportional set size when
`/proc/<pid>/smaps_rollup` is readable.

Measure:

1. Peak process-tree RSS/PSS for `sync`, `doctor`, `setup` simulation and
   `uninstall` simulation.
2. Idle `inotifywait` RSS/PSS and CPU.
3. Zen aggregate RSS/PSS with 1, 4 and 8 windows before and after loading the
   integration.
4. Memory before, during and after a 100-change burst to detect growth/leaks.
5. Rust binary size, stripped size and mapped private/ shared pages.

Sample for at least ten minutes in leak scenarios and retain the time series.
The previously observed `inotifywait` RSS of roughly 4 MiB is only an informal
observation; replace it with controlled baseline data.

### Result layout

Create a stable artifact tree such as:

```text
docs/benchmarks/rust-migration/
  methodology.md
  baseline-v1.4.0/
    environment.json
    summary.md
    latency.csv
    cpu.csv
    memory.csv
  phase-1-sync/
  phase-2-cli/
  final-rust/
  comparison.md
```

Do not commit machine-sensitive paths, usernames or unrelated process data.
Normalize paths and profile identifiers as the existing bridge does.

## Migration phases

### Phase 0: freeze and measure Bash behavior

- Write the complete current-runtime reference.
- Extend benchmark tooling for CPU, RAM, failure counts and environment data.
- Add fixture-driven contract tests for every command.
- Capture and commit the controlled `v1.4.0` baseline.
- Identify noise and rerun unstable scenarios before writing Rust code.

Exit gate: the baseline is reproducible from documentation and raw samples can
regenerate every reported statistic.

### Phase 1: Rust scaffold and `sync`

- Add the pinned workspace and a candidate binary with no installer switch.
- Implement configuration/path resolution, strict colors parsing, canonical
  palette generation, permissions and same-directory atomic replacement.
- Differentially execute Bash and Rust against identical fixtures and compare
  bytes, modes, event patterns, outputs and exit statuses.
- Benchmark Bash and Rust binaries directly, then benchmark the mixed dispatcher.
- Keep JavaScript validation unchanged.

Exit gate: complete sync parity, no security regression, and measured benefit.

### Phase 2: read-only commands

- Migrate `help`, `status` and `doctor`, including exact `doctor --json`
  semantics and bridge-log parsing.
- Add golden JSON plus semantic human-output tests.
- Confirm malformed and stale installations produce equivalent severities.

Exit gate: parity tests cover every diagnostic branch and resource results show
no material regression.

### Phase 3: state-changing user commands

- Migrate `disable`, `enable` and `set`.
- Preserve event order, atomic palette generation, Omarchy argument handling
  and restoration behavior on failure.
- Re-run inotify, fallback and multi-window benchmarks.

Exit gate: live Zen tests pass without restart and without duplicate applies.

### Phase 4: setup, ownership and uninstall

- Migrate these last because they have the highest data-loss and privilege risk.
- Preserve staged activation, exact-file ownership, historical hash adoption,
  backups, unknown-file refusal, symlink/path defenses and partial-failure
  recovery.
- Test exclusively in disposable roots before any live installation.
- Include update from `v1.4.0`, failed update, downgrade and uninstall cases.

Exit gate: all lifecycle tests pass and destructive targets remain explicitly
bounded and recoverable.

### Phase 5: switch the default CLI

- Replace the dispatcher only after all commands pass parity.
- Keep the shell hook as a tiny `exec omazen sync` compatibility entry point.
- Remove migrated Bash only after at least one full mixed-mode qualification.
- Run the complete final benchmark campaign and write `comparison.md`.

Exit gate: release gate, live installation gate and all performance acceptance
criteria pass.

### Optional phase: watcher ownership

Only evaluate a Rust `watch` subcommand if eliminating `inotify-tools` is a
product requirement. Compare it against the current single `inotifywait`
process for idle CPU, RSS/PSS, startup latency, event latency, process failure,
multi-window sharing and security. Do not adopt it merely because Rust exists.

## Acceptance criteria

Correctness and safety are mandatory:

- Zero known behavioral differences unless explicitly approved and documented.
- Byte-identical canonical palette output for all accepted fixtures.
- Equivalent rejection of malformed/unknown input and unsafe filesystem state.
- `OMAZEN_SKIP_THEME_HOOK=1` works through setup, persistence, sync, doctor,
  update and uninstall.
- Healthy inotify, watcher failure, 5-second safety polling and 250 ms fallback
  all remain covered.
- No additional privileged interface, local port, FFI or page-visible API.
- No lost backups, broadened delete target or unowned-file overwrite.

Performance criteria should be applied to medians and tails, not one sample:

- Migrated `sync` should improve p50 by at least 30% versus Bash and must not
  worsen p95 or p99.
- `sync-to-apply` p95 must not regress by more than 5% or 2 ms, whichever is
  larger; the target is an improvement.
- Atomic event-to-apply p95/p99 must not materially regress because that path
  remains JavaScript/inotify.
- Idle CPU with healthy watcher must remain statistically indistinguishable
  from baseline; no new periodic wakeup is acceptable.
- CLI aggregate CPU time must not regress by more than 10%.
- Peak process-tree memory must not regress by more than 2 MiB or 20%, whichever
  is larger, without an explicit documented tradeoff.
- Ten-minute idle and burst tests must show no monotonic memory growth.
- Binary size and dependency count are reported even when not release blockers.

If noise exceeds a criterion, rerun under controlled conditions; do not declare
success or failure from an unstable comparison.

## Commit and review strategy

Use small commits that preserve a runnable tree:

1. Baseline methodology, harness and raw results.
2. Rust toolchain/workspace scaffold.
3. Contract fixtures and differential runner.
4. One migrated command or cohesive command family per commit.
5. Dispatcher switch separately from implementation.
6. Final benchmark/comparison documentation.
7. Removal of obsolete Bash only after qualification.

Run the relevant parity and benchmark gate before each commit and the complete
release gate before each phase boundary. Never rewrite or discard unrelated
user changes.

## Final deliverables

- Complete current-runtime architecture and compatibility reference.
- Pinned Rust 1.98.0 workspace and lockfile.
- Incrementally migrated CLI with no Rust/Gecko FFI.
- Differential contract suite covering Bash and Rust during coexistence.
- Reproducible latency, CPU and RAM harness.
- Raw baseline, per-phase and final measurements.
- A comparison report identifying improvements, neutral changes and regressions.
- Updated install, security, compatibility, release and rollback documentation.
- Clean release gate and documented live test results.
