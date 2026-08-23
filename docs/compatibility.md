# Compatibility

| Target | Status |
|---|---|
| Omarchy 4.0.0 / Quattro | Supported and tested |
| `zen-browser-bin 1.21.15b-1` | Supported and tested |
| Native Zen >= 1.20 | Candidate; doctor warns as untested |
| Native Zen < 1.20 | Rejected |
| Zen Flatpak | Outside MVP |
| Firefox | Outside MVP |
| AppImage/tarball Zen | Detection can be added later; outside MVP |

## Package updates

The privileged autoconfig bootstrap necessarily resides in the Zen application directory. A `zen-browser-bin` upgrade can replace it. Omazen does not edit package-owned files in the background, install an automatic root hook, or fetch a moving upstream branch. After an upgrade:

```bash
omazen doctor
omazen setup   # only if doctor reports owned loader files missing
```

The setup operation is idempotent. It reuses an intact compatible loader, updates only Omazen-owned profile files, and never overwrites `userChrome.css`, `userContent.css` or `user.js`.

## Selector maintenance

Zen-specific selectors and `--zen-*` variables are not a stable public API. The current CSS was checked against the installed 1.21.15b `browser/omni.ja`. A future Zen build may keep the bridge operational while individual surfaces stop matching. Compatibility updates should inspect the exact package's `zen-styles` files and extend CSS only under Omazen's scope attribute.

## Known MVP boundaries

- Browser chrome, URL bar, tabs, sidebar, workspace controls, popups, split containers, Glance containers and relevant internal pages are targeted.
- Ordinary website content is deliberately not recolored; only vertical and horizontal scrollbar colors are mapped to the active palette.
- Zen Boost storage is deliberately not mutated.
- No WebExtension/native-messaging alternative is shipped because the privileged PoC succeeded and the alternate backend has not yet demonstrated equivalent Zen-specific coverage.
