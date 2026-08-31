# Compatibility

## Official support scope

The official Omazen compatibility contract is **Omarchy Quattro + the native Arch
`zen-browser-bin` package** installed at `/opt/zen-browser-bin`. Compatibility
claims below apply only to that combination. Omazen does not claim support for
other Zen packaging formats or for Firefox.

`OMAZEN_ACTIVE_COLORS` together with `OMAZEN_SKIP_THEME_HOOK=1` is a narrow
integration interface for external palette providers. It skips only the
Omarchy hook; all browser, palette, ownership and diagnostic checks remain in
effect. Using that interface does not make the external desktop environment
part of Omazen's official support contract.

After a successful `setup`, Omazen persists the provider mode and active colors
path under its state directory. Explicit environment variables override the
persisted values for that invocation. External providers still own the timing
of subsequent `omazen sync` calls.

The event-driven path uses the fixed `/usr/bin/inotifywait` binary supplied by
`inotify-tools`. Its absence does not break palette synchronization: the bridge
logs `WATCHER_FALLBACK` and retains the previous 250 ms polling path. This
watcher behavior is independent of `OMAZEN_SKIP_THEME_HOOK`; an external
provider that invokes `omazen sync` produces the same atomic event as the
Omarchy hook.

## Compatibility contract

| Target | Contract |
|---|---|
| Omarchy 4.0.2 / Quattro | Supported; current tested environment 2026-08-31 |
| Omarchy 3.x and earlier | Incompatible; rejected by `omazen setup` and `omazen doctor` |
| `zen-browser-bin 1.21.16b-1` | Supported; full validation 2026-08-31 |
| Native `zen-browser-bin` Zen >= 1.20 | Compatibility candidate; `omazen doctor` warns unless it is the fully validated version above |
| Native Zen < 1.20 | Rejected by `omazen setup` and `omazen doctor` |

The full live qualification recorded below was performed on Omarchy `4.0.0-1`.
After subsequent system updates, Omarchy `4.0.2` is the current tested Quattro
environment and Zen `1.21.16b` is the current fully validated browser version.

The only fully validated Zen version in this release is `1.21.16b` (package
`1.21.16b-1`). The candidate range is native `zen-browser-bin` Zen `>=1.20`;
being in that range means that setup may proceed, not that the version is
stable or covered by the release guarantee.

### New and unknown Zen versions

A native Zen version `>=1.20` that is not listed as fully validated is treated
as an **unknown compatibility candidate**. Omazen allows setup to proceed and
`omazen doctor` emits a warning, but the version must not be described as
supported until it has been tested. After every package update, run:

```bash
omazen doctor
omazen setup   # only if doctor reports owned loader files missing
```

An unknown build may keep the bridge working while changing Zen's private
selectors or internal pages. Such changes can cause partial styling or a
broken integration; they are compatibility issues to diagnose and validate,
not a promise made by this release. A version below `1.20`, or a version that
cannot be detected, is not a candidate and is rejected.

### Explicit exclusions

The following are outside the supported scope and have no support commitment:

- Zen Flatpak.
- Firefox.
- Zen AppImage, tarball, source builds, or other non-native package formats.

## Package updates

The privileged autoconfig bootstrap necessarily resides in the Zen application directory. A `zen-browser-bin` upgrade can replace it. Omazen does not edit package-owned files in the background, install an automatic root hook, or fetch a moving upstream branch. After an upgrade:

```bash
omazen doctor
omazen setup   # only if doctor reports owned loader files missing
```

The setup operation is idempotent. It reuses an intact compatible loader, updates only Omazen-owned profile files, and never overwrites `userChrome.css`, `userContent.css` or `user.js`.

## Selector maintenance

Zen-specific selectors and `--zen-*` variables are not a stable public API. The current CSS was checked against the installed 1.21.16b `browser/omni.ja`. A future Zen build may keep the bridge operational while individual surfaces stop matching. Compatibility updates should inspect the exact package's `zen-styles` files and extend CSS only under Omazen's scope attribute.

## Known product boundaries

- Browser chrome, URL bar, tabs, sidebar, workspace controls, popups, split containers, Glance containers and relevant internal pages are targeted.
- Ordinary website content is deliberately not recolored; only vertical and horizontal scrollbar colors are mapped to the active palette.
- A web page's `<select>` dropdown is content UI even though Firefox renders it as a chrome `menupopup`. It keeps Zen's stock palette so it continues to follow the page's own color scheme.
- Zen Boost storage is deliberately not mutated.
- No WebExtension/native-messaging alternative is shipped because the privileged backend has proven reliable and the alternate backend has not demonstrated equivalent Zen-specific coverage.
