# Research and upstream audit

Research date: 2026-08-22. Local observations are tied to the package versions in the PoC report; upstream links are pinned where practical.

## Omarchy Quattro

The current Omarchy checkout audited was commit [`eca89f9518a95fbb279fcf55567d4d6df38e6d2e`](https://github.com/basecamp/omarchy/tree/eca89f9518a95fbb279fcf55567d4d6df38e6d2e).

The current [theming documentation](https://github.com/basecamp/omarchy/blob/eca89f9518a95fbb279fcf55567d4d6df38e6d2e/docs/theming.md) and [`omarchy-theme-set`](https://github.com/basecamp/omarchy/blob/eca89f9518a95fbb279fcf55567d4d6df38e6d2e/bin/omarchy-theme-set) show that Quattro now stages a theme under `~/.local/state/omarchy/current/next-theme`, moves it to `~/.local/state/omarchy/current/theme`, then invokes `omarchy-hook theme-set "$THEME_NAME"`. Consequently, the current palette path is:

```text
~/.local/state/omarchy/current/theme/colors.toml
```

Older `~/.config/omarchy/current` and `~/.local/share/omarchy/themes/...` assumptions are not used. The hook is installed through [`omarchy hook install`](https://github.com/basecamp/omarchy/blob/eca89f9518a95fbb279fcf55567d4d6df38e6d2e/bin/omarchy-hook-install) into `~/.config/omarchy/hooks/theme-set.d/`.

All 22 stock palettes on the audited Omarchy 4.0.0 system define the same core semantic keys: `mode`, `accent`, `selection`, `muted`, four background stops, four foreground stops and named terminal colors. A few themes add border-related override keys; these are optional.

### Internal palette mapping

| Omazen JSON | Quattro source | Reason |
|---|---|---|
| `mode` | `mode` | Canonical `dark` or `light` signal |
| `accent` | `accent` | Primary interactive/accent color |
| `background` | `background` | Primary surface |
| `background_dark` | `dark_background` | Deeper surface |
| `background_light` | `lighter_background` | Raised surface |
| `foreground` | `foreground` | Primary readable text |
| `foreground_muted` | `muted` | Quattro's semantic de-emphasis token |
| `selection` | `selection` | Selected text/control surface |
| `border` | `active_border_color`, else `muted` | Optional explicit simple border, with semantic fallback |

All colors must be six-digit hex values. JSON output is canonical, mode-constrained, permission `0600`, and atomically renamed within the state directory.

## Installed Zen Browser

The audited native package was `zen-browser-bin 1.21.15b-1`:

- wrapper: `/usr/bin/zen-browser`
- application: `/opt/zen-browser-bin/zen`
- profile registry: `~/.config/zen/profiles.ini`
- profile roots: relative to `~/.config/zen/`
- source repository recorded by the binary: [zen-browser/desktop](https://github.com/zen-browser/desktop)
- source stamp recorded by the binary: `cee4147767801299dec330c81318c01e5a39e6ec`

Inspection of the installed `browser/omni.ja` confirmed current Zen CSS surfaces for toolbar, omnibox, vertical tabs, workspaces, split view, Glance, popups, compact mode and panels. Stable variables used by Omazen include `--zen-primary-color`, `--zen-colors-primary`, `--zen-colors-secondary`, `--zen-colors-tertiary`, `--zen-colors-border`, `--zen-main-browser-background`, `--zen-toolbar-element-bg` and `--zen-split-view-active-tab-bg`. Selectors are scoped below `:root[data-omazen-enabled="true"]` so disabling Omazen restores Zen's own cascade.

Zen's own `ZenActorsManager.sys.mjs` uses parent/child actors for Mods Marketplace, Glance, window drag and Boosts. Mozilla documents `JSWindowActor` as the Fission-safe parent/child communication primitive for frames in [Firefox Source Docs](https://firefox-source-docs.mozilla.org/dom/ipc/jsactors.html). Zen's official [live editing guide](https://docs.zen-browser.app/guides/live-editing) confirms the supported approach for discovering current chrome selectors, but CSS alone cannot observe an external palette file.

## zen-wabi audit

Current `main` was commit [`4b42ce351504f95de53aaf57d6bf70df85e0dd53`](https://github.com/parazeeknova/zen-wabi/tree/4b42ce351504f95de53aaf57d6bf70df85e0dd53). It includes substantial Matugen templates, documentation, and a copied fx-autoconfig runtime, but its three decisive JavaScript paths are symbolic links to a sibling `doty` repository that is not included:

```text
fx-autoconfig/profile/chrome/JS/matugen-bridge.uc.js
fx-autoconfig/profile/chrome/JS/Matugen/MatugenParent.sys.mjs
fx-autoconfig/profile/chrome/JS/Matugen/MatugenChild.sys.mjs
```

All three links are broken in a clean clone. The latest commit replaced roughly 1,400 lines with those links. The immediately preceding commit [`9fb21eaa097bd3056ed92d4c1c310f79201aed49`](https://github.com/parazeeknova/zen-wabi/tree/9fb21eaa097bd3056ed92d4c1c310f79201aed49) still materializes bridge 1.7 and both actor modules, so it was inspected to understand the architecture.

Reusable architectural lessons were: keep state in the parent process, poll atomic file replacement, apply chrome variables in every window, use actors for process-separated documents, and push the current state when a new document loads. Components not reused were Matugen preferences, Quickshell state, wallpaper switching, GitHub-specific CSS, universal Boost creation, per-domain storage mutation, external `theme_switcher`, external dotfiles and force-kill installation instructions.

Omazen's bridge and actors were written from scratch around a fixed ten-key contract and an internal-page allowlist. zen-wabi is neither a dependency nor a source-code payload.

## fx-autoconfig audit

The pinned upstream is [`dfdab5684faffc112b76ccb1d8cab7f75da0102c`](https://github.com/MrOtherGuy/fx-autoconfig/tree/dfdab5684faffc112b76ccb1d8cab7f75da0102c), loader version `0.10.16`, MPL 2.0.

Its two layers are intentionally kept separate:

- program files: `config.js` and `defaults/pref/config-prefs.js` under the Zen application directory;
- profile files: `chrome/utils/*`, which register and load scripts only for profiles that contain them.

The experimental `@WindowActor` metadata is gated by `userChromeJS.experimental.enabled`. Omazen enables it with an isolated program preference drop-in instead of editing `user.js`. The upstream [README warning](https://github.com/MrOtherGuy/fx-autoconfig/blob/dfdab5684faffc112b76ccb1d8cab7f75da0102c/readme.md) is accurate and central: any process able to modify profile loader scripts can inject privileged browser logic.

The installer reuses an exact or structurally compatible existing loader, but refuses to overwrite or automatically merge a foreign autoconfig. No update URL is executed by Omazen and no component is fetched at runtime.
