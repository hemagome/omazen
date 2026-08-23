# Architecture

```text
omarchy theme set
  -> ~/.config/omarchy/hooks/theme-set.d/theme-set
  -> omazen sync
  -> ~/.local/state/omarchy/current/theme/colors.toml
  -> same-directory temporary JSON + atomic rename
  -> ~/.local/state/omazen/palette.json
  -> privileged bridge in every Zen chrome window (250 ms fixed-file poll)
  -> strict schema and color validation
  -> CSS variables + Omazen-scoped chrome stylesheet
  -> allowlisted Omazen JSWindowActor
  -> allowlisted about: pages and internal dialog documents
```

## State contract

```json
{
  "schema_version": 1,
  "mode": "dark",
  "accent": "#89b4fa",
  "background": "#1e1e2e",
  "background_dark": "#181825",
  "background_light": "#313244",
  "foreground": "#cdd6f4",
  "foreground_muted": "#6c7086",
  "selection": "#45475a",
  "border": "#585b70"
}
```

The bridge rejects missing keys, unknown keys, wrong schema versions, non-object JSON, modes other than `dark`/`light`, colors other than `#RRGGBB`, and files outside 2–2048 bytes. The JSON cannot supply paths, selectors, CSS or executable text.

## Window behavior

fx-autoconfig injects `omazen-bridge.uc.js` into each top-level browser chrome document. Every browser window therefore owns a small watcher and applies the current palette to itself. The bridge observes only the exact `Browser:About`, `Places:Organizer` and `devtools:toolbox` window types and applies the same validated palette to existing or later-created About Zen, Library and Developer Tools windows; other auxiliary windows are ignored. A later-created browser window reads the existing JSON during initial injection.

The actor is registered only for a fixed list of internal `about:` documents plus Zen's Spotlight, Firefox's common-dialog and Print documents, and the `chrome://devtools/content/` namespace. This covers Passwords, Translations, Print, Remote Debugging and the in-browser Developer Tools without granting access to ordinary content. It reads validated palette preferences when the actor is created and at `DOMContentLoaded`, and accepts only `Omazen:Apply` messages matching the same strict color contract. It is not registered for `http:`, `https:`, arbitrary extension pages or other chrome namespaces.

Passwords, Print and some Developer Tools documents can run in isolated processes that do not instantiate the custom actor. The bridge therefore also registers a Firefox user sheet generated from a fixed template and scoped with `@-moz-document` to the exact Passwords, Translations, Print and DevTools URL families. It is replaced atomically when the palette changes and unregistered on disable; it never matches web origins. Print's preview canvas and document remain unmodified, and its system-dialog link continues to hand off to the external GTK/portal surface.

## Enable and disable

`omazen disable` creates the fixed `~/.local/state/omazen/disabled` marker. Each bridge removes its scope attribute and variables, sets the internal-page preference to disabled and broadcasts a disable message. `omazen enable` removes that marker and atomically rewrites the palette. No restart is involved.

## Installation ownership

Omazen records only files it created in `~/.local/state/omazen/owned/`, including an expected SHA-256. Upgrades back up owned files before replacement. Uninstall deletes a recorded file only when its current hash still matches the recorded hash; modified files are retained with a warning. Identical pre-existing files are reused but not claimed.
