# Release validation report

## 1.3.1 maintenance release

Date: 2026-08-25
Release: Omazen `1.3.1`

This maintenance release fixes the native XUL context-menu active-row state so
its hover background and text use the Omazen selection and foreground palette
instead of Zen's native blue highlight.

The complete `tests/release-gate.sh` passed: static analysis, release
consistency, all 12 disposable lifecycle scenarios, rendered-pixel smoke and
whitespace checks. The real installation updated both detected Zen profiles,
removed the owned `1.3.0` styles, retained the timestamped application backup,
and synchronized the active palette. After a normal Zen restart, `omazen
doctor --json` reported bridge `1.3.1` loaded with zero failures and zero
warnings.

## 1.1.1 maintenance release

Omazen `1.1.1` contains release automation, test and documentation updates,
plus versioned identifiers for the unchanged runtime. The automated
`tests/release-gate.sh` passed for this release. No new live browser
qualification was required; the validated `1.1.0` runtime baseline below
remains applicable.

## Validated 1.1.0 runtime baseline

Date: 2026-08-24
Release: Omazen `1.1.0`

## Result

Omazen `1.1.0` passed the automated and live release gates. The qualification
repeated the surfaces and state transitions most affected by the hardened
bridge, observer, palette and installation lifecycle. The exhaustive `1.0.0`
surface pass and its screenshots remain below as the visual baseline; the PoC
remains available only as historical evidence for the original backend
decision.

The final state is Omazen installed and enabled, Zen running bridge `1.1.0`,
`omazen doctor` reporting zero failures and warnings, and the original Osaka
Jade theme restored.

## 1.1.0 release qualification

| Gate | Observation | Result |
|---|---|---|
| Staged update | `./install.sh` removed both profiles' obsolete `v1.0.0` styles, activated `1.1.0`, and retained the previous application as `omazen.backup.20260824T185458Z.110154`. | Pass |
| Restart and bridge | After Zen was restarted, the log recorded `BRIDGE_LOADED version=1.1.0`, `PALETTE_APPLIED`, and `CHROME_CSS_APPLIED`; the final doctor run reported `0 failure(s), 0 warning(s)`. | Pass |
| Live dark/light | Osaka Jade changed to Catppuccin Latte in PID `6485`; the bridge logged `accent=#1e66f5 mode=light` and applied chrome CSS without restarting Zen. Returning to Osaka Jade logged `accent=#509475 mode=dark` in the same PID. | Pass |
| Disable/enable | `disable` logged `DISABLED` and produced the expected doctor warning. `enable` reapplied the light palette and returned doctor to zero warnings without changing PID `6485`. | Pass |
| Representative surfaces | Inspected Settings in both modes, Passwords with an empty profile, Debugging, the clear-data dialog, Library and Print. The destructive dialog and Print were cancelled; no credentials, browsing data, PDF or print job were touched. | Pass |
| Automated gate | `tests/syntax.sh`, all 12 functional scenarios, `tests/visual-smoke.sh`, and `git diff --check` passed after the live review. | Pass |

Together, the exhaustive `1.0.0` baseline and the focused `1.1.0`
requalification cover dark and light palettes, live palette changes in both
directions, live disable/enable, normal Zen restarts, every Settings subsection
visible in the tested build, dialogs, Library, Passwords, Print, Developer
Tools, web scrollbars, and real update/uninstall/clean-install exercises.

## Environment

| Component | Observed value |
|---|---|
| Omazen | `1.1.0` |
| Omarchy | `4.0.0-1` (Quattro) |
| Zen package | `zen-browser-bin 1.21.15b-1` |
| Zen build ID | `20260818101929` |
| Gecko milestone | `154.0` |
| fx-autoconfig | loader `0.10.16`, commit `dfdab5684faffc112b76ccb1d8cab7f75da0102c` |
| Dark palette | Osaka Jade: `mode=dark`, `accent=#509475`, `background=#111c18` |
| Light palette | Catppuccin Latte: `mode=light`, `accent=#1e66f5`, `background=#eff1f5` |
| Zen profiles | 2 profiles from the active `profiles.ini` |

## Current compatibility environment

Updated: 2026-08-25

The system used for current compatibility checks has been updated from Omarchy
`4.0.0-1` to Omarchy `4.0.1` (Quattro). The full live qualification above is
historical and remains labeled with the version on which it was executed; the
Zen, fx-autoconfig and Omazen runtime versions are unchanged.

## Combined functional matrix

| Area | Exercise and observation | Result |
|---|---|---|
| Dark theme | Started with Osaka Jade and inspected browser chrome, Settings controls, text, focus states, cards and scrollbars. | Pass |
| Light theme | Switched to Catppuccin Latte and repeated the same surface checks. | Pass |
| Live theme change | The `1.0.0` baseline passed both directions. In `1.1.0`, Osaka Jade → Catppuccin Latte → Osaka Jade kept Zen PID `6485` and logged the expected light and dark `PALETTE_APPLIED` plus `CHROME_CSS_APPLIED` events. | Pass |
| Disable and enable | Both releases logged `DISABLED`, reverted open chrome, and reapplied the current palette on enable without changing the tested Zen PID. The final `1.1.0` doctor run returned to zero warnings. | Pass |
| Zen restart | The `1.0.0` baseline restart passed, and the `1.1.0` deployment restart subsequently logged `BRIDGE_LOADED version=1.1.0`, `PALETTE_APPLIED` and `CHROME_CSS_APPLIED`. | Pass |
| Settings | Opened all 16 subsections visible in this build: Look and Feel, Tab Management, Keyboard Shortcuts, Zen Mods, Account and sync, Home and startup, Search, Privacy and security, Passwords and autofill, Appearance, Downloads, Tabs and browsing, Accessibility, Languages, Permissions and data, and About Zen. | Pass |
| Dialogs | Opened the Clear browsing data and cookies modal, checked the surface, labels, checkboxes, selector and primary/secondary actions, then cancelled it without deleting data. | Pass |
| Library | Opened the separate Library window and checked History, Downloads, Tags, bookmark tree, toolbar, search and empty state. | Pass |
| Passwords | Opened `about:logins` and checked its search, list/sidebar, empty state and Sync action. The tested profile contained zero saved passwords, so no credential data was displayed or captured. | Pass |
| Print | Opened Print on the local scrollbar fixture; checked preview, destination, orientation, pages, color mode, More settings, system-dialog link and Save/Cancel actions. No print or PDF job was submitted. | Pass |
| More Tools | Opened the Inspector from Developer Tools and checked the docked toolbox, tabs, notification bar, DOM tree, rules and computed/layout panels. Disable/enable was also exercised while the toolbox was open. | Pass |
| Web scrollbars | Opened the local `file:` fixture with deliberate vertical and horizontal overflow. The browser-provided thumb/track followed the Omazen palette while the document background and content retained their native colors. | Pass |
| Automated regression suite | `tests/test.sh` completed all 12 TAP scenarios, including runtime repair and conflicts, strict doctor checks, palette failure handling, observer filtering and cleanup, staged update recovery, backup and uninstall. | Pass |
| Real update | The `1.0.0` qualification update passed. The `1.1.0` staged update additionally removed obsolete versioned styles, created `~/.local/share/omazen.backup.20260824T185458Z.110154`, synchronized the palette and completed with zero doctor failures after restart. | Pass |
| Real uninstall | In the `1.0.0` baseline, closed Zen, ran `./uninstall.sh`, and verified that the command link, application copy, state, hook, owned profile runtime and three owned program files were absent. The `1.1.0` equivalent also passes in the disposable lifecycle suite. | Pass |
| Clean install | In the `1.0.0` baseline, installed from an uninstalled state, verified source/installed SHA-256 equality for all three program files, and reopened Zen successfully. The `1.1.0` clean-install path also passes in the disposable lifecycle suite. | Pass |

## Exhaustive 1.0.0 visual baseline

### Dark and light Settings

| Osaka Jade (dark) | Catppuccin Latte (light) |
|---|---|
| ![Dark Settings](images/validation-2026-08-24/dark-settings.png) | ![Light Settings](images/validation-2026-08-24/light-settings.png) |

### Every visible Settings subsection

![Light Settings subsection contact sheet](images/validation-2026-08-24/light-settings-subsections.png)

### Auxiliary surfaces

| Dialog | Library | Passwords |
|---|---|---|
| ![Clear browsing data dialog](images/validation-2026-08-24/light-common-dialog.png) | ![Library window](images/validation-2026-08-24/light-library.png) | ![Passwords](images/validation-2026-08-24/light-passwords.png) |

| Print | More Tools / Developer Tools | Web scrollbars |
|---|---|---|
| ![Print preview](images/validation-2026-08-24/light-print.png) | ![Developer Tools](images/validation-2026-08-24/light-more-tools.png) | ![Web scrollbar fixture](images/validation-2026-08-24/light-web-scrollbars.png) |

### Live state and restart

| Disabled | Re-enabled | After restart |
|---|---|---|
| ![Omazen disabled](images/validation-2026-08-24/light-disabled.png) | ![Omazen enabled](images/validation-2026-08-24/light-enabled.png) | ![Omazen after Zen restart](images/validation-2026-08-24/light-after-restart.png) |

### Automated rendered-pixel smoke test

The repository also contains a fast, repeatable browser smoke test for the
production content stylesheet:

```bash
tests/visual-smoke.sh
```

It starts the installed `zen-browser` binary with a disposable profile,
loads `tests/fixtures/visual-smoke.html`, captures a fixed `1000x768` viewport
and checks the rendered pixels for the document surface, header, card, action
button, input, scroll content and scrollbar thumb. It then invokes
`tests/visual-integration.sh` when Wayland/Hyprland capture tools are available.
That integration pass copies the production fx-autoconfig runtime into another
disposable profile, boots a real Zen window on `about:preferences`, captures
the browser chrome and Settings regions for dark/light palettes, exercises
live palette changes plus disable/enable, verifies persisted palette
preferences and compares captures with a bounded ImageMagick tolerance. It
never uses the live profile or network. To retain the capture for review:

```bash
OMAZEN_KEEP_VISUAL_OUTPUT=1 \
OMAZEN_VISUAL_OUTPUT_DIR=/tmp/omazen-visual-capture \
  tests/visual-smoke.sh
```

### Automated palette contrast check

`node tests/contrast.mjs` scans all available Omarchy `colors.toml` files and
uses the same WCAG relative-luminance implementation as the runtime-derived
accent button foreground. Primary button text and selection text are enforced
at 4.5:1; link, muted-text and scrollbar combinations are emitted as
warnings until their surface-specific semantics are finalized. In CI without
an Omarchy installation, two edge-case fixtures exercise both black and white
accent foreground fallbacks. `--strict` promotes all warning groups to
failures for a local accessibility audit.

## Reproduction checklist

1. Record `omazen status`, `omazen doctor`, the current theme, Zen version and Zen PID.
2. Open Settings and visit every visible subsection listed in the matrix.
3. With Zen open, switch once to a palette with the opposite `mode`; verify the PID is unchanged and wait for both `PALETTE_APPLIED` and `CHROME_CSS_APPLIED`.
4. Run `omazen disable`, verify native styling returns, then run `omazen enable` and verify the palette returns without a PID change.
5. Exercise the non-destructive auxiliary surfaces: cancel dialogs and Print, do not save or delete credentials/data, and close Library normally.
6. Open `tests/fixtures/web-scrollbars.html`; verify both overflow axes and confirm that page content is not recolored.
7. Close the last Zen window normally, reopen it, and require a new `BRIDGE_LOADED` plus successful CSS application in `bridge.log`.
8. Run `tests/test.sh` for the disposable lifecycle.
9. For a release qualification on a test machine, run the real update, uninstall and clean install; verify exact owned paths before each destructive step and finish with `omazen doctor` plus a normal Zen start.

## Final state

The test machine was left in the supported state:

- Omazen `1.1.0` installed and enabled.
- Zen running with bridge `1.1.0` loaded.
- `omazen doctor`: `0 failure(s), 0 warning(s)` after the live release review.
- Original Osaka Jade theme restored and applied live.
- The `1.1.0` pre-update application backup remains at `~/.local/share/omazen.backup.20260824T185458Z.110154` for recovery.
