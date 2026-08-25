# Omazen

Omazen hot-reloads the active Omarchy Quattro palette into Zen Browser without
restarting Zen after the one-time privileged-loader setup.

The runtime normalizes Quattro colors into a fixed JSON file, applies them to
Zen chrome through a privileged bridge, and uses allowlisted WindowActors for
supported internal pages. It has no runtime downloads, local server or
page-exposed API. See the [architecture](docs/architecture.md) and
[security model](docs/security.md) for details.

## Current status

Omazen `1.1.1` is a maintenance release; its runtime is unchanged from the
qualified `1.1.0` build. The current tested environment is Omarchy `4.0.1`
(Quattro) with native `zen-browser-bin 1.21.15b-1`.

The historical live qualification and complete test results are recorded in
the [validation report](docs/validation.md). Compatibility boundaries and
unsupported Zen packaging formats are listed in the
[compatibility guide](docs/compatibility.md).

## Install

Review [the security model](docs/security.md), then run:

```bash
./install.sh
```

Close Zen normally and open it once after initial setup. Theme changes after
that are live and do not require a restart.

The installer writes only Omazen-owned files and never edits
`userChrome.css`, `userContent.css` or `user.js`.

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
- `sync` regenerates the normalized palette from the active Quattro theme.
- `set "Theme Name"` delegates to `omarchy theme set` and synchronizes.
- `doctor` checks compatibility, installation integrity, palette freshness and
  bridge health.
- `disable` and `enable` update open windows without restarting Zen.
- `uninstall` removes only unchanged files recorded as Omazen-owned.

Transitions default to 180 ms, respect reduced-motion settings, and can be disabled in `about:config` with `omazen.transitions.enabled=false`.

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

Run the complete pre-release gate, including static analysis, regression tests,
the rendered-pixel smoke test and whitespace checks, with:

```bash
tests/release-gate.sh
```

See the [release checklist](docs/release.md) for deployment and publication.

## License

Omazen source code is licensed under GPL-3.0-only, with the required attribution
notice in [NOTICE](NOTICE). Vendored fx-autoconfig files remain under MPL 2.0;
see [third-party notices](THIRD_PARTY_LICENSES.md).
