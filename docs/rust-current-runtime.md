# Omazen v1.4.1 runtime contract

This document freezes the Bash implementation that the incremental Rust CLI
must preserve. The executable specification remains the disposable lifecycle
suite in `tests/test.sh`; this reference records the behavior that is easy to
lose during a rewrite.

## Process and event flow

```text
omarchy theme set
  -> sequential theme-set hooks
  -> hooks/theme-set execs omazen sync
  -> colors.toml subset is normalized
  -> private same-directory temporary palette
  -> chmod 0600 and atomic rename to palette.json
  -> process-wide inotifywait observes MOVED_TO
  -> every subscribed bridge validates and applies the palette
  -> delayed CSS diagnostic
```

The healthy watcher uses one fixed `/usr/bin/inotifywait` child per Zen process
and a five-second safety poll. If that child cannot start or exits, each bridge
falls back to a 250 ms fixed-file poll. `PALETTE_APPLIED` marks completed palette
application. `CHROME_CSS_APPLIED` is a later computed-style diagnostic and is
not the first moment at which the CSS takes effect.

## Commands and exit behavior

- `help`, `-h`, `--help`, and no arguments print the same usage to stdout.
- An unknown command prints usage and an `ERROR:` line to stderr and exits 1.
- `setup`, `sync`, `status`, `disable`, `enable`, and `uninstall` reject any
  argument. `doctor` accepts only `--json`; `set` accepts zero or one quoted
  theme name.
- `sync` normalizes the selected colors file and publishes `palette.json`.
- `set THEME` runs `omarchy theme set THEME` and then synchronizes; `set`
  without an argument only synchronizes.
- `disable` creates a private marker. `enable` writes a valid palette before
  removing that marker so the bridge never re-enables without usable state.
- `status` is concise human output. `doctor` reports all applicable checks and
  exits nonzero when any check fails. `doctor --json` uses schema version 1 and
  retains the same check severities and fields.
- `setup` and `uninstall` operate only on supported, explicitly bounded paths
  and recorded ownership. Partial or unsafe work returns nonzero.

Normal results go to stdout. Warnings and `ERROR:` diagnostics go to stderr.
Existing wording, ordering, arity, and exit codes are compatibility contracts.

## Configuration and precedence

Explicit environment values win. Otherwise Omazen reads private persisted
`active-colors` and `provider-mode` state. Missing state falls back to XDG paths
and Omarchy's active theme:

1. explicit `OMAZEN_ACTIVE_COLORS` or `OMAZEN_SKIP_THEME_HOOK`;
2. persisted state under `${XDG_STATE_HOME:-$HOME/.local/state}/omazen`;
3. `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme/colors.toml`
   and provider mode `0`.

`OMAZEN_SKIP_THEME_HOOK=1` skips only hook installation. It does not skip
palette synchronization, persistence, the Zen loader, watcher, diagnostics,
ownership tracking, update, or uninstall. Only `0` and `1` are accepted.

The test-only path overrides (`OMAZEN_HOME_DIR`, `OMAZEN_STATE_DIR`,
`OMAZEN_ZEN_CONFIG_DIR`, `OMAZEN_ZEN_PROGRAM_DIR`, `OMAZEN_HOOKS_DIR`,
`OMAZEN_DATA_DIR`, `OMAZEN_LOCAL_BIN_DIR`, `OMAZEN_OS_RELEASE_FILE`,
`OMAZEN_ZEN_VERSION_OVERRIDE`, `OMAZEN_SKIP_PACKAGE_CHECK`, and
`OMAZEN_TESTING`) must remain usable for disposable qualification.

## Palette contract

The accepted input is deliberately narrower than general TOML. Blank lines and
comments are ignored. A recognized assignment has an ASCII alphanumeric or
underscore key, `=`, and one double-quoted value, with optional surrounding
space and trailing comment. Unrecognized lines are ignored and a duplicate key
uses its last recognized value. `mode` must be `dark` or `light`; the required
colors must be exactly `#RRGGBB`. `active_border_color` is optional and falls
back to `muted` when absent or invalid.

The output has schema version 1, a fixed key order, two-space indentation,
lowercase colors, and one trailing newline. It is exactly 12 lines and at most
2048 bytes. State directories are mode `0700`; state files and temporaries are
mode `0600`. The temporary is created beside the destination and publication is
an atomic rename, which must continue producing the `MOVED_TO` event consumed by
the bridge.

## Profiles, installation, and ownership

Profiles come from an explicit `OMAZEN_PROFILE` or `profiles.ini`. Relative
entries are constrained to the canonical Zen configuration root; escaping paths
are ignored. Omazen supports Omarchy Quattro and native `zen-browser-bin`,
refuses a conflicting autoconfig installation, and requires compatible
fx-autoconfig program and profile components.

Every claimed file is recorded as `path|sha256` in a private manifest. Identical
pre-existing files are reused without claiming them. Unknown files are never
overwritten. Owned files are backed up before replacement and are deleted only
when their current hash still matches the manifest. Modified owned files remain
with a warning. Known historical preference files may be adopted only by an
allowlisted byte-exact SHA-256.

Repository stylesheet sources are the stable `omazen-chrome.css` and
`omazen-content.css`. Setup installs them as release-versioned profile files to
defeat `chrome://` caches. Updating to v1.4.1 removes obsolete stylesheet files
only when the ownership manifest and hash authorize removal; modified or
unknown versions remain in place.

The top-level installer stages a complete application copy beside the active
destination. Only after successful setup does it atomically exchange the active
copy and retain the previous copy as a timestamped backup. Failed staging leaves
the active application unchanged. Application self-removal requires both the
installed marker and an exact canonical match with the configured data root;
the filesystem root and home directory are forbidden targets.

Privileged program files use the existing `sudo`/`pkexec` boundary. The Rust
migration must not expand that boundary, follow unsafe symlinks, introduce a
daemon, local server, Gecko FFI, or page-visible API.

## Stable boundary during migration

```text
shell hook -> exec CLI -> atomic palette.json -> inotify -> JavaScript
```

The Gecko bridge, WindowActors, shared JavaScript palette validation, CSS, and
watcher remain unchanged. A pre-source dispatcher may select Rust for migrated
commands and Bash for the rest. The shell hook remains a minimal `exec omazen
sync` compatibility entry point until a separately measured product decision
changes that contract.
