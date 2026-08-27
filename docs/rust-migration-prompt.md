# Prompt for the Rust migration task

Copy the text below into a new Codex chat opened on the
`codex/rust-migration-plan` branch.

---

Continue the Omazen Rust migration on the existing
`codex/rust-migration-plan` branch. Read
`docs/rust-migration-plan.md` completely before taking implementation actions
and treat it as the migration contract.

The objective is to migrate Omazen's Bash CLI incrementally to a single binary
built with exactly Rust 1.98.0, while preserving behavior, security and rollback
and producing controlled before/after evidence for latency, CPU and RAM. Do not
rewrite the Gecko JavaScript, WindowActors or CSS in Rust, do not add Rust/Gecko
FFI, and do not introduce a daemon or replace `inotifywait` unless the optional
watcher phase is separately justified by measurements after the CLI migration.

Start by auditing the repository at the branch head and confirming the working
tree, current version, available tools and active Zen/Omarchy environment. The
first implementation milestone is Phase 0, not Rust code:

1. Document the complete current `v1.4.1` runtime, including command behavior,
   file formats, atomic writes, environment precedence, installation ownership,
   privilege boundaries, `OMAZEN_SKIP_THEME_HOOK`, watcher lifecycle, safety
   polling, fallback and the distinction between palette application and the
   delayed CSS diagnostic. Treat `v1.4.1` as the baseline wherever the migration
   plan still refers to `v1.4.0`.
2. Extend the benchmark tooling to capture reproducible raw latency, CPU and
   RAM data as specified in the plan. Include process-tree accounting, 1/4/8
   window scenarios, healthy inotify and polling fallback, idle and burst
   workloads, and full theme changes that restore the original theme.
3. Capture the Bash baseline before adding Rust implementation code. Use at
   least 100 measured latency samples and 200+ where p99 is a decision metric,
   at least three runs, ten-minute idle/leak samples, and a complete environment
   manifest. Store normalized raw data and generated summaries under
   `docs/benchmarks/rust-migration/baseline-v1.4.1/`.
4. Make the benchmark report regenerate entirely from raw samples. Do not hide
   timeouts or discard outliers. Record watcher backend and all warnings.

After the baseline is complete and reproducible, implement the phases in order:

- Add `rust-toolchain.toml` pinned to `1.98.0`, Rust 2024 edition,
  `rust-version = "1.98"`, a Cargo workspace and committed lockfile.
- Add differential contract tests before switching each command.
- Migrate `sync` first, preserving byte-identical canonical JSON, `0600` files,
  `0700` state directories, same-directory temporary files, atomic rename and
  the `MOVED_TO` event expected by the bridge.
- Migrate read-only `help`, `status` and `doctor` next.
- Migrate `disable`, `enable` and `set` after that.
- Migrate `setup` and `uninstall` last, only after exhaustive disposable-root
  tests for manifests, backups, known historical preference adoption, unknown
  file refusal, symlinks, partial failures, downgrade and rollback. Preserve the
  `v1.4.1` stylesheet contract: canonical repository sources remain unversioned,
  installed profile stylesheets remain release-versioned, owned obsolete
  versions such as `v1.4.0` are removed on update, and modified or unknown files
  are never silently overwritten or deleted.
- Use a pre-source `exec` dispatcher while Bash and Rust coexist. Avoid FFI.
- Keep the shell `theme-set` hook as a minimal compatibility wrapper.
- Preserve the exact semantics and precedence of `OMAZEN_SKIP_THEME_HOOK=1`.

For every phase:

1. Run correctness/parity tests first.
2. Run the same before/after benchmark scenarios.
3. Compare p50/p95/p99 latency, aggregate CPU and process-tree RSS/PSS.
4. Investigate every regression rather than averaging it away.
5. Update the comparison documentation with raw evidence.
6. Commit atomically with a runnable tree and retain rollback.

Use the acceptance thresholds in `docs/rust-migration-plan.md`. In particular,
target at least 30% lower `sync` p50, no p95/p99 regression, no new idle wakeup,
no meaningful event-to-apply regression, no leak, and no unapproved safety or
behavior difference. A language rewrite by itself is not a success criterion.

Run `cargo fmt --check`, Clippy with warnings denied, all Cargo tests, existing
Bash/JavaScript tests, differential tests and the complete release gate at phase
boundaries. Record the exact Rust compiler metadata and dependency licenses.

Do not publish a release, merge to `main`, remove the Bash fallback, alter the
real `/opt` installation, or perform live theme changes without first ensuring
the baseline/restore procedure is safe. Continue autonomously through safe
repository and disposable-environment work; stop only when a required live
system mutation, missing authority or genuinely material product choice needs
user direction.

At handoff, report:

- commits and migrated commands;
- parity status and known differences;
- baseline versus Rust p50/p95/p99;
- CPU and RAM comparisons;
- regressions and mitigations;
- remaining phases and exact blockers;
- links to raw data and generated reports.

---
