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
| Omarchy 4.5.0-3 / Quattro RS | Supported; locally validated 2026-11-12 with native Zen 1.24.2b-1 |
| Omarchy 4.0.6 / Quattro | Previously validated 2026-10-30; remains in the supported 4.x line |
| Omarchy 3.x and earlier | Incompatible; rejected by `omazen setup` and `omazen doctor` |
| `zen-browser-bin 1.24.2b-1` | Supported; locally validated 2026-11-12 with Omarchy 4.5.0-3 |
| `zen-browser-bin 1.24b-1` | Previously validated 2026-10-30; remains recognized as supported |
| `zen-browser-bin 1.23.2b-1` | Previous validated browser; reported as a candidate by current Omazen releases |
| Native `zen-browser-bin` Zen >= 1.20 | Compatibility candidate; `omazen doctor` warns unless it matches a fully validated version above |
| Native Zen < 1.20 | Rejected by `omazen setup` and `omazen doctor` |

The full live qualification recorded below was first performed on Omarchy
`4.0.0-1`, then revalidated on Omarchy `4.0.6` with native Zen `1.24b` on
2026-10-30. The current environment, Omarchy `4.5.0-3` with native Zen
`1.24.2b-1`, passed the rendered-pixel smoke and compositor-backed integration
on 2026-11-12, including live dark-to-light changes and disable/enable. This
current run used the CSS contract checks for the empty-tab and pre-paint rules
added in PR #5 and exercised the live Zen integration on this version. The
compositor test does not assert a dedicated empty-tab pixel.

Release `1.6.3` originally pinned `doctor` and the verified CI browser archive
to Zen `1.24b`. The diagnostic now recognizes both `1.24b` and `1.24.2b` as
fully validated; the CI archive remains pinned to `1.24b` pending a verified
digest for the newer archive. Previous CLI releases, including `1.6.3`, still
warn that Zen `1.24.2b` is a candidate until Omazen is rebuilt with this update.
The candidate range is native `zen-browser-bin` Zen `>=1.20`; being in that
range means setup may proceed, not that the version is stable or covered by the
release guarantee.

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

Zen-specific selectors and `--zen-*` variables are not a stable public API. The existing CSS was checked against the installed 1.24b `browser/omni.ja`: all 19 referenced `--zen-*` variables remain present across its 36 `zen-styles` CSS files. The 2026-11-12 integration additionally ran against the installed 1.24.2b package and exercised the browser chrome and Settings rendering. A future Zen build may keep the bridge operational while individual surfaces stop matching. Compatibility updates should inspect the exact package's `zen-styles` files and extend CSS only under Omazen's scope attribute.

## Known product boundaries

- Browser chrome, URL bar, tabs, sidebar, workspace controls, popups, split containers, Glance containers and relevant internal pages are targeted.
- Ordinary website content is deliberately not recolored; only vertical and horizontal scrollbar colors are mapped to the active palette.
- A web page's `<select>` dropdown is content UI even though Firefox renders it as a chrome `menupopup`. It keeps Zen's stock palette so it continues to follow the page's own color scheme.
- Zen Boost storage is deliberately not mutated.
- No WebExtension/native-messaging alternative is shipped because the privileged backend has proven reliable and the alternate backend has not demonstrated equivalent Zen-specific coverage.
