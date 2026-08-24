# Omazen

Omazen hot-reloads the active Omarchy Quattro palette into Zen Browser without restarting Zen after the one-time privileged-loader setup.

The supported runtime is intentionally small: Bash reads Quattro's semantic `colors.toml` and atomically writes a normalized JSON file; a constrained privileged JavaScript bridge watches that fixed file; CSS variables restyle Zen chrome; and a `JSWindowActor` limited to an allowlist of `about:` pages updates relevant internal pages. There is no Node.js, Python, Rust, Go, Matugen, Sine, WebExtension, remote code download or local server in the runtime path.

The canonical release number is stored in `VERSION`; CI checks every embedded
bridge version and versioned stylesheet URI against it.

## Current status

Omazen `1.1.1` is a maintenance release containing release automation and
documentation improvements. Its runtime is unchanged from the `1.1.0` build,
which passed the automated syntax, release-consistency, functional and
rendered-pixel suites, plus the live Zen release gate on 24 August 2026:

- Omarchy `4.0.0-1` (Quattro)
- `zen-browser-bin 1.21.15b-1`
- Zen build ID `20260818101929`, Gecko `154.0`
- fx-autoconfig `0.10.16`, pinned to commit `dfdab5684faffc112b76ccb1d8cab7f75da0102c`

The `1.1.0` build passed a real staged update, bridge restart/version validation,
dark and light live changes, live disable/enable, Settings, dialogs, Library,
Passwords, Print and Developer Tools. The exhaustive `1.0.0` visual baseline and
real lifecycle qualification remain recorded alongside the `1.1.0` delta in the
[validation report](docs/validation.md). The earlier
[proof-of-concept report](docs/proof-of-concept.md) is retained as historical
backend evidence.

## Install

Review [the security model](docs/security.md) first. Then run:

```bash
./install.sh
```

The installer copies Omazen to `~/.local/share/omazen`, creates `~/.local/bin/omazen`, installs the Omarchy `theme-set` hook, integrates the pinned fx-autoconfig loader, and installs only Omazen-owned files in every profile listed by Zen's `profiles.ini`.

Close Zen normally and open it once after initial setup. Theme changes after that are live and do not require a restart.

Omazen never edits `userChrome.css`, `userContent.css` or `user.js`. It stops on an unowned autoconfig conflict instead of merging privileged startup code automatically.

## Commands

```text
omazen setup
omazen sync
omazen set [theme]
omazen status
omazen doctor
omazen disable
omazen enable
omazen uninstall
```

- `setup` installs or repairs the integration idempotently.
- `sync` regenerates `~/.local/state/omazen/palette.json` from the active Quattro palette.
- `set "Theme Name"` delegates to `omarchy theme set` and synchronizes.
- `doctor` checks Zen, profiles, fx-autoconfig, installed-file integrity and permissions,
  palette freshness, bridge version and errors, and known compatibility.
- `disable` and `enable` take effect on open windows at the next 250 ms poll.
- `uninstall` removes only files recorded as Omazen-owned and refuses to delete modified files.

Top-level installs and updates are assembled in a sibling staging directory.
`setup` must succeed before an existing application copy is moved to a timestamped
backup and the staged copy is activated, so removed release files cannot linger.

Transitions default to 180 ms, respect reduced-motion settings, and can be disabled in `about:config` with `omazen.transitions.enabled=false`.

## Compatibility

The official support scope is **Omarchy Quattro plus the native Arch package `zen-browser-bin`** at `/opt/zen-browser-bin`. This release fully validates only Zen `1.21.15b` (`zen-browser-bin 1.21.15b-1`). Native Zen versions `>=1.20` are compatibility candidates: unknown newer versions may pass setup, but `omazen doctor` warns and they are not supported until tested. Flatpak, Firefox, AppImage, tarball, source-build, and other non-native Zen installations are outside the supported scope. Run `omazen doctor` after every Zen update; package upgrades may replace the program-level loader files and `omazen setup` repairs an owned installation.

See [compatibility details](docs/compatibility.md), [architecture](docs/architecture.md), and [research notes](docs/research.md).

## Development

Contributions are welcome. Please read the [contribution guide](.github/CONTRIBUTING.md),
follow the [Code of Conduct](.github/CODE_OF_CONDUCT.md), and use the repository's
pull request template when opening a change.

CI uses Node.js 24 plus pinned ShellCheck 0.11.0 and actionlint 1.7.12
binaries. To reproduce static analysis locally on Linux x86-64:

```bash
tests/install-linters.sh /tmp/omazen-linters
PATH=/tmp/omazen-linters:$PATH tests/lint.sh
```

The test suite uses only a disposable filesystem tree:

```bash
tests/test.sh
```

It covers palette mapping, idempotent setup, preservation of pre-existing user files, live enable/disable state, ownership-aware uninstall, refusal to overwrite a foreign autoconfig, and the top-level install/update/uninstall lifecycle.

The rendered-pixel smoke test uses the installed Zen binary and a disposable profile:

```bash
tests/visual-smoke.sh
```

It loads the production content stylesheet in a real headless Zen window and checks pixels from the resulting screenshot. To keep the capture for inspection, set `OMAZEN_KEEP_VISUAL_OUTPUT=1` and `OMAZEN_VISUAL_OUTPUT_DIR` to an explicit directory.

To run the complete pre-release gate locally, including static analysis,
functional tests, the visual smoke test and whitespace checks:

```bash
tests/release-gate.sh
```

The release tag is derived from `VERSION` by `tests/create-release-tag.sh`,
which rejects dirty worktrees, mismatched embedded versions and missing
changelog sections.

Before publishing a release, follow the [release checklist](docs/release.md).

## License

Omazen source code is licensed under the GNU General Public License version 3.0 only (GPL-3.0-only), with the required attribution notice in [NOTICE](NOTICE). Distributed modified versions of Omazen must remain under the GPL and provide the corresponding source code.

The vendored fx-autoconfig files remain under MPL 2.0 and are kept in a separate directory with their upstream license, exact commit and checksums. They are not relicensed under the GPL. See [third-party notices](THIRD_PARTY_LICENSES.md).
