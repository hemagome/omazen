# Command reference

Omazen exposes its complete CLI through `omazen <command>`. Run `omazen help`
to print the same command summary locally.

## Setup and synchronization

### `omazen setup`

Installs or repairs the Zen integration. Setup validates the supported platform
and Zen version, updates Omazen-owned files, configures the Omarchy theme hook
and synchronizes the active palette. It is safe to run again when repairing an
installation after a Zen package update.

### `omazen sync`

Validates the active `colors.toml` and atomically regenerates the normalized
palette consumed by open Zen windows.

### `omazen set [theme]`

Delegates a quoted theme name to `omarchy theme set` and then synchronizes the
new palette:

```bash
omazen set "Theme Name"
```

With no theme argument, it synchronizes the currently active theme without
changing it:

```bash
omazen set
```

## Status and diagnostics

### `omazen status`

Prints concise installation and runtime state, including the Omazen and Zen
versions, provider mode, palette state, detected profiles and latest bridge
event.

### `omazen doctor [--json]`

Checks platform and Zen compatibility, installation integrity, profile state,
palette freshness and bridge health:

```bash
omazen doctor
omazen doctor --json
```

Use `--json` for schema-versioned, machine-readable diagnostics suitable for
automation and bug reports.

### `omazen report [--output PATH]`

Creates a timestamped `.tar.gz` support package in the current directory. The
archive contains sanitized doctor and status output, relevant versions, a
bounded bridge-log fragment and SHA-256 metadata for installed files.

```bash
omazen report
omazen report --output /path/to/report.tar.gz
```

Omazen refuses to overwrite an existing report. Inspect the archive before
sharing it.

## Runtime control

### `omazen disable`

Disables Omazen live without removing installed files. Open Zen windows revert
automatically.

### `omazen enable`

Synchronizes the active palette and re-enables Omazen. Open Zen windows update
automatically.

## Uninstall

### `omazen uninstall`

Removes files recorded as Omazen-owned. Modified files and shared
fx-autoconfig loaders are retained rather than removed unsafely; the command
reports any leftovers requiring manual review. Existing `userChrome.css`,
`userContent.css` and `user.js` files are never removed.

## External palette providers

External desktop integrations can provide a trusted local `colors.toml` while
skipping only the Omarchy hook:

```bash
OMAZEN_ACTIVE_COLORS=/absolute/path/to/colors.toml \
OMAZEN_SKIP_THEME_HOOK=1 \
omazen setup
```

Omazen persists that provider configuration after setup. The external provider
is responsible for invoking `omazen sync` after palette changes. This interface
does not expand Omazen's official compatibility scope; see the
[compatibility guide](compatibility.md#official-support-scope).
