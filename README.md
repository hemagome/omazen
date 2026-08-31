# Omazen

[![CI](https://github.com/hemagome/omazen/actions/workflows/ci.yml/badge.svg)](https://github.com/hemagome/omazen/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/hemagome/omazen?display_name=tag&sort=semver)](https://github.com/hemagome/omazen/releases)
[![License](https://img.shields.io/badge/license-GPL--3.0--only-blue.svg)](LICENSE)

Live Omarchy Quattro palette synchronization for Zen Browser through a
security-conscious privileged bridge.

## Features

- Applies active Omarchy palette changes to open Zen windows without a restart.
- Themes browser chrome and supported internal pages while leaving ordinary web
  content alone.
- Uses no runtime downloads, local server or page-exposed API, and provides
  ownership-aware setup, diagnostics and uninstall.

## Requirements

Omazen officially supports **Omarchy Quattro with the native Arch
`zen-browser-bin` package**. Other Zen packaging formats and Firefox are outside
the supported scope. See the [compatibility guide](docs/compatibility.md) for
validated versions and known boundaries.

> [!IMPORTANT]
> Omazen installs privileged browser code. Review the
> [security model](docs/security.md) before installing it.

## Install

Download the Linux x86-64 archive and its `.sha256` sidecar from the
[latest release](https://github.com/hemagome/omazen/releases/latest). Close Zen,
then replace `X.Y.Z` below with the downloaded version:

```bash
sha256sum --check omazen-X.Y.Z-linux-x86_64.tar.gz.sha256
tar -xzf omazen-X.Y.Z-linux-x86_64.tar.gz
cd omazen-X.Y.Z-linux-x86_64
./install.sh
```

Open Zen once to load the integration, then verify the installation:

```bash
omazen doctor
```

Release archives include the compiled CLI, so installed users do not need Rust.
Building from a source checkout requires the toolchain documented in the
[contribution guide](.github/CONTRIBUTING.md).

## Quick start

```bash
omazen set "Theme Name"  # Change the Omarchy theme and synchronize it
omazen status            # Show concise runtime state
omazen doctor            # Check compatibility and integration health
```

Run `omazen help` for the complete command list or read the
[command reference](docs/commands.md). To remove the integration and only its
owned files, run `omazen uninstall`.

Using another local palette provider? See the narrowly scoped
[external-provider interface](docs/compatibility.md#official-support-scope).

## Documentation

- [Command reference](docs/commands.md)
- [Compatibility](docs/compatibility.md)
- [Security model](docs/security.md)
- [Architecture](docs/architecture.md)
- [Validation report](docs/validation.md)
- [Latency benchmark](docs/benchmark.md)

## Support

Use [GitHub Discussions](https://github.com/hemagome/omazen/discussions) for
questions and support. For a reproducible bug, run `omazen report`, inspect the
generated archive, and attach it to a
[bug report](https://github.com/hemagome/omazen/issues/new/choose).

## Contributing

See the [contribution guide](.github/CONTRIBUTING.md) for environment setup,
tests and pull-request requirements.

## License

Omazen source code is licensed under GPL-3.0-only; see [LICENSE](LICENSE) and
[NOTICE](NOTICE). Vendored fx-autoconfig files remain under MPL 2.0; see the
[third-party notices](THIRD_PARTY_LICENSES.md).
