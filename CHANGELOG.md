# Changelog

All notable changes to Omazen are documented here.

## [Unreleased]

### Added

- A release tag helper derives `v<version>` from the canonical `VERSION` file
  and shares its validation rules with the GitHub publication workflow.
- External palette providers can set `OMAZEN_ACTIVE_COLORS` and opt out of the
  Omarchy theme hook with `OMAZEN_SKIP_THEME_HOOK=1` while retaining the full
  loader, validation, diagnostics, and ownership model.

### Changed

- Compatibility documentation now records Omarchy 4.0.1 as the current tested
  Quattro environment while preserving the historical 4.0.0-1 qualification.
- Omarchy 3 and earlier are now rejected before setup changes are made because
  their generated theme state uses the pre-Quattro path layout.

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
