# Changelog

All notable changes to Omazen are documented here.

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
