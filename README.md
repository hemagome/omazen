# Omazen

Omazen hot-reloads the active Omarchy Quattro palette into Zen Browser without
restarting Zen after the one-time privileged-loader setup.

The runtime normalizes Quattro colors into a fixed JSON file, applies them to
Zen chrome through a privileged bridge, and uses allowlisted WindowActors for
supported internal pages. A shared `inotifywait` subprocess wakes every open
Zen window after atomic palette updates; fixed-file polling remains only as a
failure fallback and a low-frequency safety check. It has no runtime downloads,
local server or page-exposed API. See the [architecture](docs/architecture.md) and
[security model](docs/security.md) for details.

## Current status

Omazen `1.5.0` runs its complete CLI as a directly installed Rust executable,
removing the former Bash implementation and launcher overhead while preserving
the qualified command and rollback contracts. Canonical stylesheet sources
remain unversioned in the repository and are installed under release-versioned
names for `chrome://` cache busting. The shared event-driven watcher, automatic
polling fallback and external palette-provider compatibility remain intact. The
current tested environment is Omarchy `4.0.1` (Quattro) with native
`zen-browser-bin 1.21.15b-1`.

The historical live qualification and complete test results are recorded in
the [validation report](docs/validation.md). Compatibility boundaries and
unsupported Zen packaging formats are listed in the
[compatibility guide](docs/compatibility.md).

## Install

Review [the security model](docs/security.md), then run:

```bash
./install.sh
```

The installer uses a bundled `libexec/omazen-rust` release payload when present
and installs it directly as `bin/omazen`; there is no shell launcher on the
command path. A source checkout without the prebuilt payload requires the
pinned Rust 1.98.0 toolchain once at build time; installed users do not need
Rust or Cargo at runtime. Published Linux x86-64 release archives include the
prebuilt binary and a SHA-256 sidecar.

Close Zen normally and open it once after initial setup. Theme changes after
that are live and do not require a restart.

External desktop integrations that provide an Omazen-compatible `colors.toml`
may opt out of installing the Omarchy hook while retaining Omazen's loader,
palette validation, diagnostics and ownership tracking:

```bash
OMAZEN_ACTIVE_COLORS=/absolute/path/to/colors.toml \
OMAZEN_SKIP_THEME_HOOK=1 \
omazen setup
```

Setup persists the provider mode and active palette source under Omazen's state
directory. Explicit environment variables still take precedence for that
invocation; later `sync` calls use the saved configuration. The external
provider owns triggering `omazen sync` after palette changes. This is an
integration interface, not an expansion of Omazen's official support scope.

The installer writes only Omazen-owned files and never edits
`userChrome.css`, `userContent.css` or `user.js`.

## Commands

```text
omazen setup
omazen sync
omazen set [theme]
omazen status
omazen doctor [--json]
omazen disable
omazen enable
omazen uninstall
```

- `setup` installs or repairs the integration idempotently.
- `sync` regenerates the normalized palette from the active Quattro theme.
- `set "Theme Name"` delegates to `omarchy theme set` and synchronizes.
- `doctor` checks compatibility, installation integrity, palette freshness and
  bridge health. `doctor --json` emits the same checks as a structured report
  for bug reports and automation.
- `disable` and `enable` update open windows without restarting Zen.
- `uninstall` removes only unchanged files recorded as Omazen-owned.

The event-driven fast path uses `/usr/bin/inotifywait` from `inotify-tools`.
When it is unavailable or exits unexpectedly, the bridge automatically returns
to the previous 250 ms polling behavior.

## Compatibility

The official support scope is **Omarchy Quattro plus the native Arch package
`zen-browser-bin`** installed at `/opt/zen-browser-bin`. Zen `1.21.15b` is the
fully validated version; native Zen versions `>=1.20` are compatibility
candidates and produce a `doctor` warning until tested. Flatpak, Firefox,
AppImage, tarball, source-build and other non-native installations are outside
the supported scope. Omarchy 3 and earlier are rejected because their generated
theme state uses paths incompatible with Omazen's Quattro palette integration.

Run `omazen doctor` after every Zen update. See the
[compatibility guide](docs/compatibility.md) for the complete contract.

## Development

Read the [contribution guide](.github/CONTRIBUTING.md) before making changes.

Run the disposable functional suite with:

```bash
tests/test.sh
```

Run the WCAG palette contrast checks with:

```bash
node tests/contrast.mjs
```

The checker scans installed Omarchy `colors.toml` files (or the paths in
`OMAZEN_CONTRAST_PALETTE_DIR`) and falls back to edge-case fixtures when the
provider is not installed. Primary button and selection checks are enforced;
link, muted-text and scrollbar findings are reported as warnings while their
surface-specific semantics are being refined. Use `--strict` or
`OMAZEN_CONTRAST_STRICT=1` to promote warnings to failures.

The visual smoke command first runs the deterministic headless fixture and,
when Wayland/Hyprland capture tools are available, also runs
`tests/visual-integration.sh`. The integration pass boots a real Zen runtime
with a disposable profile, captures Settings and browser chrome for dark and
light palettes, exercises live palette changes plus disable/enable, and
compares the captures with a bounded tolerance. Set
`OMAZEN_SKIP_VISUAL_INTEGRATION=1` only for environments without a compositor.

Run the complete pre-release gate, including static analysis, regression tests,
the rendered-pixel smoke test and whitespace checks, with:

```bash
tests/release-gate.sh
```

To measure the current live-update latency with Zen open, see the
[benchmark guide](docs/benchmark.md) and run:

```bash
tests/benchmark.sh --mode all --iterations 20
```

See the [release checklist](docs/release.md) for deployment and publication.

## License

Omazen source code is licensed under GPL-3.0-only, with the required attribution
notice in [NOTICE](NOTICE). Vendored fx-autoconfig files remain under MPL 2.0;
see [third-party notices](THIRD_PARTY_LICENSES.md).
