# Omazen

Omazen hot-reloads the active Omarchy Quattro palette into Zen Browser without restarting Zen after the one-time privileged-loader setup.

The supported MVP is intentionally small at runtime: Bash reads Quattro's semantic `colors.toml` and atomically writes a normalized JSON file; a constrained privileged JavaScript bridge watches that fixed file; CSS variables restyle Zen chrome; and a `JSWindowActor` limited to an allowlist of `about:` pages updates relevant internal pages. There is no Node.js, Python, Rust, Go, Matugen, Sine, WebExtension, remote code download or local server in the runtime path.

## Current status

The proof of concept and the packaged MVP were both verified on 22 August 2026 with:

- Omarchy `4.0.0-1` (Quattro)
- `zen-browser-bin 1.21.15b-1`
- Zen build ID `20260818101929`, Gecko `154.0`
- fx-autoconfig `0.10.16`, pinned to commit `dfdab5684faffc112b76ccb1d8cab7f75da0102c`

The palette changed twice in an already-open Zen window, with the same process ID and no restart. See [the proof-of-concept report](docs/proof-of-concept.md).

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
- `doctor` checks Zen, profiles, fx-autoconfig, preferences, hook, palette, bridge load, last error and known compatibility.
- `disable` and `enable` take effect on open windows at the next 250 ms poll.
- `uninstall` removes only files recorded as Omazen-owned and refuses to delete modified files.

Transitions default to 180 ms, respect reduced-motion settings, and can be disabled in `about:config` with `omazen.transitions.enabled=false`.

## Compatibility

The MVP supports the native Arch package `zen-browser-bin` at `/opt/zen-browser-bin`. Flatpak is explicitly outside the MVP because its sandbox does not provide this privileged autoconfig path. Versions from Zen 1.20 onward are treated as compatibility candidates, but only 1.21.15b is marked as PoC-tested by this release. Run `omazen doctor` after every Zen update; package upgrades may replace the program-level loader files and `omazen setup` repairs an owned installation.

See [compatibility details](docs/compatibility.md), [architecture](docs/architecture.md), and [research notes](docs/research.md).

## Development

The test suite uses only a disposable filesystem tree:

```bash
tests/test.sh
```

It covers palette mapping, idempotent setup, preservation of pre-existing user files, live enable/disable state, ownership-aware uninstall, and refusal to overwrite a foreign autoconfig.

## License

Omazen is MIT licensed. The vendored fx-autoconfig files remain under MPL 2.0 and are kept in a separate directory with their upstream license, exact commit and checksums. See [third-party notices](THIRD_PARTY_LICENSES.md).

