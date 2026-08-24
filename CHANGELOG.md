# Changelog

All notable changes to Omazen are documented here.

## [Unreleased]

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
  packaging formats remain outside the MVP.

### Fixed

- `omazen doctor` no longer reports an old bridge error after a later
  successful bridge load, palette application or CSS probe.
