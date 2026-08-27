# Security model

Omazen deliberately installs privileged browser code. This is more powerful than a Zen Mod or WebExtension and must be treated like startup code.

## Trust boundary

fx-autoconfig allows JavaScript under a profile's `chrome` directory to execute with browser privileges. A malicious process that can modify those files can take over the browser context. Omazen does not make that mechanism safe; it minimizes and documents its use.

Installed privileged files per Zen profile:

```text
chrome/utils/boot.sys.mjs
chrome/utils/chrome.manifest
chrome/utils/fs.sys.mjs
chrome/utils/module_loader.mjs
chrome/utils/uc_api.sys.mjs
chrome/utils/utils.sys.mjs
chrome/JS/omazen-bridge.uc.js
chrome/JS/Omazen/OmazenParent.sys.mjs
chrome/JS/Omazen/OmazenChild.sys.mjs
chrome/JS/Omazen/omazen-chrome-v1.3.2.css
chrome/JS/Omazen/omazen-content-v1.3.2.css
```

Program-level files for the supported Zen package:

```text
/opt/zen-browser-bin/config.js
/opt/zen-browser-bin/defaults/pref/config-prefs.js
/opt/zen-browser-bin/defaults/pref/omazen-prefs.js
```

The first two may be reused from a compatible pre-existing fx-autoconfig installation. Omazen never silently replaces a foreign program config or partial profile runtime.

## Reductions

- No remote download, update or execution at runtime.
- Dependencies are pinned by commit and SHA-256.
- The visual CI job pins the Zen release version and verifies its SHA-256 before
  extraction or execution; the archive's version metadata remains a separate
  defense-in-depth check.
- No `eval`, dynamic import path, local port, native-messaging host or page-exposed API.
- Palette and log paths are fixed; JSON cannot select a path. Logging is bounded
  to the active `bridge.log` plus one rotated `bridge.log.1` archive.
- JSON is size-limited and strictly validated before use.
- Only normalized colors and mode cross the actor boundary.
- The actor matches a fixed internal-page allowlist and the built-in DevTools chrome namespace, never ordinary web origins.
- Most CSS is static and shipped with Omazen. For isolated Passwords, Print and DevTools processes, the eight strictly validated hex colors and validated mode are inserted into fixed, URL-scoped internal-page rules. The same generated user sheet contains a separate fixed rule for `http:`, `https:` and `file:` documents that can set only `scrollbar-color`; it provides no script, DOM access or page-exposed API. JSON cannot supply selectors, property names or URLs in either scope.
- Logs contain timestamps, fixed event names, mode, accent, a stable opaque
  profile identifier and validation errors—not URLs, page titles, profile paths
  or browsing data.
- Logs rotate at 128 KiB.
- Disable is live and uninstall is ownership/hash aware.
- External palette-provider mode can skip the Omarchy hook, but it does not
  bypass palette validation, fixed paths, loader integrity, or ownership
  checks. The external provider must supply a trusted local `colors.toml` path
  and invoke synchronization itself.

## Updates

Zen package upgrades can replace program-level files. Omazen does not fight the package manager or auto-repair as root. Run `omazen doctor`; if the owned loader is missing, run `omazen setup` interactively. `sudo` is used only when a terminal is available, otherwise the installer asks through `pkexec`.

## Uninstall limits

If another user script is found, Omazen leaves an owned shared fx-autoconfig program loader in place rather than breaking that script. If an owned file has been modified, it is also retained. In both cases ownership records remain so the user can inspect and resolve the shared state explicitly.
