# Changelog

All notable changes to Omazen are documented here.

## [Unreleased]

### Changed

- The Rust executable is now installed directly as `bin/omazen`, removing the
  shell launcher and its process-start overhead from every CLI invocation.

### Fixed

- Web-page `<select>` dropdowns are no longer recolored. Firefox renders a
  content select popup as a chrome `menupopup` (`#ContentSelectDropdown`) but
  mirrors the page's `color-scheme` onto it and keeps `--panel-text-color` as
  the system `MenuText`. Zen maps `--panel-background-color` to
  `--arrowpanel-background`, which Omazen themes on `:root`, so the popup took
  the palette background while its text stayed `MenuText` -- rendering
  near-black on near-black for any page in a light color scheme. That popup now
  keeps Zen's stock values, restoring the documented boundary that ordinary
  website content is not recolored.

### Removed

- The obsolete Bash CLI implementation was removed after the Rust CLI passed
  differential, lifecycle, performance and live multi-window qualification.
  The Omarchy hook and the bridge's watcher-failure polling fallback remain.

## [1.4.1] - 2026-08-26

### Changed

- Chrome and content stylesheets now have stable canonical source names in the
  repository. Installation still copies them to release-versioned profile paths
  so Zen receives a fresh `chrome://` URI after upgrades without making pending
  stylesheet contributions target an obsolete release file.

### Removed

- Historical versioned stylesheet copies were removed from `main`; immutable
  release tags remain the source for older release contents.

## [1.4.0] - 2026-08-26

### Added

- A process-wide `inotifywait` watcher now wakes every open Zen bridge after
  atomic palette and enable/disable state changes. Healthy watchers reduce the
  safety poll to five seconds; startup or runtime watcher failures restore the
  previous 250 ms polling behavior automatically.
- A repeatable live-update benchmark records raw samples and reports minimum,
  p50, mean, p95, p99 and maximum latency for full `omazen sync` and isolated
  atomic-replacement scenarios.

### Changed

- Omarchy-hook and external-provider modes now share the same event-driven
  palette application path. `OMAZEN_SKIP_THEME_HOOK=1` still skips only hook
  installation and continues to rely on explicit `omazen sync` calls.

### Fixed

- Re-enabling Omazen while regenerating the palette no longer applies the same
  palette twice when the atomic replacement and disabled-marker removal events
  arrive together.
- Updates now safely adopt byte-identical historical Omazen preference
  drop-ins that predate their program-manifest entry, while continuing to
  reject unknown files at the same path.

## [1.3.2] - 2026-08-26

### Added

- WCAG palette contrast checks for installed Omarchy themes and deterministic
  fallback fixtures. Primary accent buttons now derive a readable foreground
  color without changing the provider-facing palette schema.
- Real-runtime visual integration coverage for dark and light palettes, a
  disposable profile, Settings and browser chrome captures, palette changes,
  disable/enable, and tolerant visual comparisons.

### Changed

- The visual CI job now verifies the pinned SHA-256 of the Zen release archive
  before extracting or executing the downloaded browser.
- Omazen-owned color transitions and the removed `omazen.transitions.enabled`
  preference no longer alter native Zen or page transitions.

## [1.3.1] - 2026-08-25

### Fixed

- Context-menu item hover now uses the active Omazen selection and foreground
  colors instead of Zen's native blue highlight.

## [1.3.0] - 2026-08-25

### Added

- `omazen doctor --json` emits structured checks, provider metadata, palette
  paths, bridge event age and summary counts for diagnostics and bug reports.
- Provider mode and active palette source are persisted after successful setup,
  so external palette integrations do not need to repeat their environment
  variables for every command.

### Changed

- Bridge CSS diagnostics retry briefly before reporting a stylesheet failure.
- `doctor` reports detailed palette mismatches, active palette source, bridge
  event age, current palette application and CSS primary-color state.
- Bridge events include a stable per-profile identifier without logging profile
  paths.

- `omazen doctor` now renders `[PASS]`, `[WARN]`, and `[FAIL]` status tags in
  green, yellow, and red on interactive terminals, while preserving plain
  output for redirected output, `TERM=dumb`, or `NO_COLOR`.

## [1.2.0] - 2026-08-25

### Added

- A release tag helper derives `v<version>` from the canonical `VERSION` file
  and shares its validation rules with the GitHub publication workflow.
- External palette providers can set `OMAZEN_ACTIVE_COLORS` and opt out of the
  Omarchy theme hook with `OMAZEN_SKIP_THEME_HOOK=1` while retaining the full
  loader, validation, diagnostics, and ownership model. This interface was
  contributed in [#1](https://github.com/hemagome/omazen/pull/1) by
  [@nerdislb](https://github.com/nerdislb). Thanks for the contribution!

### Changed

- Compatibility documentation now records Omarchy 4.0.1 as the current tested
  Quattro environment while preserving the historical 4.0.0-1 qualification.
- Omarchy 3 and earlier are now rejected before setup changes are made because
  their generated theme state uses the pre-Quattro path layout.

### Fixed

- Compact Mode now applies the palette to Zen's rounded background layer instead
  of the rectangular toolbox behind it, preserving the native translucent frame
  and shadows without solid corner artifacts.

## [1.1.1] - 2026-08-24

### Added

- CI now verifies the exact file set, SHA-256 hashes, upstream commit and loader
  version of the vendored `fx-autoconfig` runtime.
- Reproducible ShellCheck 0.11.0 and actionlint 1.7.12 gates use official
  release artifacts pinned by SHA-256.

### Changed

- Documentation now describes Omazen's official support scope and product
  boundaries without obsolete pre-release terminology.
- CI uses Node.js 24, `actions/checkout` 7.0.1 and `actions/setup-node` 7.0.0,
  pins both actions to full commits, drops persisted checkout credentials and
  disables the unused package-manager cache.
- CI now cancels superseded runs, times out stalled validation, supports manual
  dispatch and avoids duplicate runs when release tags are pushed.
- Release validation now has one local gate, a CI rendered-pixel job, and a tag
  workflow that publishes the GitHub Release only after all checks pass.

## [1.1.0] - 2026-08-24

### Added

- Behavioral regressions execute the production bridge and child actor across
  startup, palette updates, invalid input, enable/disable, auxiliary windows,
  observer debounce, log rotation and unload cleanup.
- A canonical root `VERSION` file and release-consistency validation for embedded
  JavaScript versions and versioned stylesheet URIs.

### Changed

- `doctor` now rejects modified, outdated, symlinked, or unsafely writable Omazen
  files, stale palettes, mismatched bridge versions, and current bridge errors.
- Bridge logging now rotates to `bridge.log.1` instead of deleting all diagnostic
  history, and shared root-palette/style operations no longer use duplicated code.
- Bridge and child actors now share one palette contract and root applicator.
- Application updates are assembled and validated in staging before replacing the
  previous copy, preventing removed files from surviving future upgrades.
- Browser-chrome mutations are filtered before scheduling internal-page
  broadcasts, and the observer and timers are released on window unload.
- Omazen-owned source code is now licensed under GPL-3.0-only with the
  required project attribution in `NOTICE`.
- Vendored `fx-autoconfig` files remain under their upstream MPL 2.0 license.

### Fixed

- `setup` now repairs an owned partial fx-autoconfig profile runtime while
  continuing to reject conflicting unowned files.
- `disable` removes Omazen's injected Shadow DOM styles and disconnects their
  observer so affected Settings cards fully return to native styling.
- `enable` and `setup` keep Omazen disabled when palette validation fails.

## [1.0.0] - 2026-08-24

First stable release.

### Added

- Live Omarchy Quattro palette synchronization for native `zen-browser-bin`.
- Scoped styling for Zen chrome, Settings, internal pages, dialogs, Library,
  Passwords, Print, Developer Tools and web scrollbars.
- Idempotent setup, live enable/disable, status and compatibility diagnostics.
- Ownership-aware update, backup and uninstall behavior.
- Release validation report covering dark/light themes, restart, auxiliary
  surfaces and the full install/update/uninstall lifecycle.
- CI checks for the shell test suite and Bash/JavaScript syntax.

### Compatibility

- Fully validated: Omarchy Quattro with `zen-browser-bin 1.21.15b-1`.
- Candidate range: native `zen-browser-bin` Zen `>=1.20`; unknown versions
  remain unvalidated and produce a `doctor` warning.
- Flatpak, Firefox, AppImage, tarball, source builds and other non-native Zen
  packaging formats remain outside the supported scope.

### Fixed

- `omazen doctor` no longer reports an old bridge error after a later
  successful bridge load, palette application or CSS probe.
