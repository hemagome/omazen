#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
OMAZEN_VERSION=$(<"$PROJECT_ROOT/VERSION")
CHROME_CSS="$PROJECT_ROOT/zen/Omazen/omazen-chrome-v${OMAZEN_VERSION}.css"
CONTENT_CSS="$PROJECT_ROOT/zen/Omazen/omazen-content-v${OMAZEN_VERSION}.css"
TEST_ROOT=$(mktemp -d /tmp/omazen-tests.XXXXXX)

cleanup() {
  case "$TEST_ROOT" in
    /tmp/omazen-tests.*) rm -rf -- "$TEST_ROOT" ;;
  esac
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$*"
}

assert_file() {
  [[ -f $1 ]] || fail "missing file: $1"
}

assert_absent() {
  [[ ! -e $1 ]] || fail "unexpected path: $1"
}

assert_same_hash() {
  [[ $(sha256sum "$1" | awk '{print $1}') == $(sha256sum "$2" | awk '{print $1}') ]] || \
    fail "hash mismatch: $1 $2"
}

FAKE_HOME="$TEST_ROOT/home"
FAKE_ZEN="$TEST_ROOT/zen-program"
FAKE_CONFIG="$FAKE_HOME/.config/zen"
FAKE_PROFILE="$FAKE_CONFIG/abc.Test Profile"
FAKE_STATE="$FAKE_HOME/.local/state/omazen"
FAKE_HOOKS="$FAKE_HOME/.config/omarchy/hooks"
FAKE_COLORS="$FAKE_HOME/.local/state/omarchy/current/theme/colors.toml"
FAKE_OS_RELEASE="$TEST_ROOT/os-release"
FAKE_OLD_OS_RELEASE="$TEST_ROOT/os-release-v3"

mkdir -p "$FAKE_ZEN/defaults/pref" "$FAKE_PROFILE/chrome" "$(dirname -- "$FAKE_COLORS")"
printf '[App]\nVersion=1.21.15b\n' >"$FAKE_ZEN/application.ini"
printf '[Profile0]\nName=Test\nIsRelative=1\nPath=abc.Test Profile\nDefault=1\n' >"$FAKE_CONFIG/profiles.ini"
cat >"$FAKE_OS_RELEASE" <<'EOF'
NAME="Omarchy"
PRETTY_NAME="Omarchy"
ID=omarchy
VERSION_ID="4.0.1"
BUILD_ID="4.0.1"
EOF
cat >"$FAKE_OLD_OS_RELEASE" <<'EOF'
NAME="Omarchy"
PRETTY_NAME="Omarchy"
ID=omarchy
VERSION_ID="3.8.4"
BUILD_ID="3.8.4"
EOF
printf 'keep-user-chrome\n' >"$FAKE_PROFILE/chrome/userChrome.css"
printf 'keep-user-js\n' >"$FAKE_PROFILE/user.js"
cp "$FAKE_PROFILE/chrome/userChrome.css" "$TEST_ROOT/userChrome.before"
cp "$FAKE_PROFILE/user.js" "$TEST_ROOT/user.before"
cat >"$FAKE_COLORS" <<'EOF'
mode = "light"
accent = "#112233"
selection = "#223344"
muted = "#334455"
background = "#fefefe"
dark_background = "#eeeeee"
darker_background = "#dddddd"
lighter_background = "#ffffff"
foreground = "#101010"
dark_foreground = "#555555"
light_foreground = "#080808"
bright_foreground = "#000000"
red = "#aa0000"
yellow = "#aaaa00"
green = "#00aa00"
cyan = "#00aaaa"
blue = "#0000aa"
magenta = "#aa00aa"
bright_red = "#ff0000"
bright_yellow = "#ffff00"
bright_green = "#00ff00"
bright_cyan = "#00ffff"
bright_blue = "#0000ff"
bright_magenta = "#ff00ff"
EOF

run_omazen() {
  OMAZEN_TESTING=1 \
  OMAZEN_SKIP_PACKAGE_CHECK=1 \
  OMAZEN_HOME_DIR="$FAKE_HOME" \
  OMAZEN_STATE_DIR="$FAKE_STATE" \
  OMAZEN_ZEN_CONFIG_DIR="$FAKE_CONFIG" \
  OMAZEN_ZEN_PROGRAM_DIR="$FAKE_ZEN" \
  OMAZEN_HOOKS_DIR="$FAKE_HOOKS" \
  OMAZEN_ACTIVE_COLORS="$FAKE_COLORS" \
  OMAZEN_OS_RELEASE_FILE="$FAKE_OS_RELEASE" \
  "$PROJECT_ROOT/bin/omazen" "$@"
}

run_omazen_with_os_release() {
  local os_release=$1
  shift
  OMAZEN_TESTING=1 \
  OMAZEN_SKIP_PACKAGE_CHECK=1 \
  OMAZEN_HOME_DIR="$FAKE_HOME" \
  OMAZEN_STATE_DIR="$FAKE_STATE" \
  OMAZEN_ZEN_CONFIG_DIR="$FAKE_CONFIG" \
  OMAZEN_ZEN_PROGRAM_DIR="$FAKE_ZEN" \
  OMAZEN_HOOKS_DIR="$FAKE_HOOKS" \
  OMAZEN_ACTIVE_COLORS="$FAKE_COLORS" \
  OMAZEN_OS_RELEASE_FILE="$os_release" \
  "$PROJECT_ROOT/bin/omazen" "$@"
}

run_external_omazen() {
  OMAZEN_SKIP_THEME_HOOK=1 run_omazen "$@"
}

run_persisted_omazen() {
  OMAZEN_TESTING=1 \
  OMAZEN_SKIP_PACKAGE_CHECK=1 \
  OMAZEN_HOME_DIR="$FAKE_HOME" \
  OMAZEN_STATE_DIR="$FAKE_STATE" \
  OMAZEN_ZEN_CONFIG_DIR="$FAKE_CONFIG" \
  OMAZEN_ZEN_PROGRAM_DIR="$FAKE_ZEN" \
  OMAZEN_HOOKS_DIR="$FAKE_HOOKS" \
  OMAZEN_OS_RELEASE_FILE="$FAKE_OS_RELEASE" \
  "$PROJECT_ROOT/bin/omazen" "$@"
}

run_omazen setup >/dev/null
assert_file "$FAKE_STATE/palette.json"
assert_file "$FAKE_ZEN/config.js"
assert_file "$FAKE_ZEN/defaults/pref/config-prefs.js"
assert_file "$FAKE_ZEN/defaults/pref/omazen-prefs.js"
assert_file "$FAKE_PROFILE/chrome/JS/omazen-bridge.uc.js"
assert_file "$FAKE_PROFILE/chrome/JS/Omazen/OmazenChild.sys.mjs"
assert_file "$FAKE_PROFILE/chrome/JS/Omazen/OmazenPalette.sys.mjs"
assert_file "$FAKE_PROFILE/chrome/JS/Omazen/omazen-chrome-v${OMAZEN_VERSION}.css"
assert_file "$FAKE_PROFILE/chrome/JS/Omazen/omazen-content-v${OMAZEN_VERSION}.css"
assert_file "$FAKE_HOOKS/theme-set.d/theme-set"
status_output=$(run_omazen status)
grep -Fq "Omazen: $OMAZEN_VERSION" <<<"$status_output" || fail "reported package version"
grep -Fq 'OS: Omarchy 4.0.1 (omarchy)' <<<"$status_output" || fail "reported supported platform"
doctor_output=$(run_omazen doctor)
grep -Fq '[PASS] supported platform: Omarchy 4.0.1 (omarchy)' <<<"$doctor_output" || \
  fail "doctor reported supported platform"
pass "status and doctor report the supported platform"

doctor_json=$(run_omazen doctor --json)
printf '%s\n' "$doctor_json" | node -e '
  const fs = require("node:fs");
  const report = JSON.parse(fs.readFileSync(0, "utf8"));
  if (!report.ok || report.provider !== "omarchy-hook" || !Array.isArray(report.checks)) process.exit(1);
' || fail "doctor JSON report shape"
pass "doctor emits a structured JSON report"

doctor_v3_output=$(run_omazen_with_os_release "$FAKE_OLD_OS_RELEASE" doctor 2>&1 || true)
grep -Fq '[FAIL] unsupported platform: Omarchy 3.8.4 (omarchy); supported platform is Omarchy Quattro (4.x)' <<<"$doctor_v3_output" || \
  fail "doctor did not reject Omarchy 3"

V3_HOME="$TEST_ROOT/v3-home"
V3_ZEN="$TEST_ROOT/v3-zen-program"
V3_CONFIG="$V3_HOME/.config/zen"
V3_PROFILE="$V3_CONFIG/abc.Test"
V3_STATE="$V3_HOME/.local/state/omazen"
V3_HOOKS="$V3_HOME/.config/omarchy/hooks"
V3_COLORS="$V3_HOME/.config/omarchy/current/theme/colors.toml"
mkdir -p "$V3_ZEN/defaults/pref" "$V3_PROFILE/chrome" "$(dirname -- "$V3_COLORS")"
printf '[App]\nVersion=1.21.15b\n' >"$V3_ZEN/application.ini"
printf '[Profile0]\nName=Test\nIsRelative=1\nPath=abc.Test\nDefault=1\n' >"$V3_CONFIG/profiles.ini"
cp "$FAKE_COLORS" "$V3_COLORS"
if OMAZEN_TESTING=1 OMAZEN_SKIP_PACKAGE_CHECK=1 \
  OMAZEN_HOME_DIR="$V3_HOME" OMAZEN_STATE_DIR="$V3_STATE" \
  OMAZEN_ZEN_CONFIG_DIR="$V3_CONFIG" OMAZEN_ZEN_PROGRAM_DIR="$V3_ZEN" \
  OMAZEN_HOOKS_DIR="$V3_HOOKS" OMAZEN_ACTIVE_COLORS="$V3_COLORS" \
  OMAZEN_OS_RELEASE_FILE="$FAKE_OLD_OS_RELEASE" \
  "$PROJECT_ROOT/bin/omazen" setup >/dev/null 2>&1; then
  fail "setup accepted Omarchy 3"
fi
assert_absent "$V3_ZEN/config.js"
assert_absent "$V3_PROFILE/chrome/JS/omazen-bridge.uc.js"
assert_absent "$V3_HOOKS/theme-set.d/theme-set"
assert_absent "$V3_STATE"
pass "Omarchy 3 is rejected before setup changes"

grep -Fq '"mode": "light"' "$FAKE_STATE/palette.json" || fail "palette mode mapping"
grep -Fq '"background_dark": "#eeeeee"' "$FAKE_STATE/palette.json" || fail "palette background mapping"
grep -Fq -- '--zen-urlbar-background-base: var(--omazen-background-light)' \
  "$CHROME_CSS" || fail "inactive URL bar background"
grep -Fq -- '--lwt-toolbar-field-focus: var(--omazen-background-light)' \
  "$CHROME_CSS" || fail "focused URL bar background"
grep -Fq -- '--zen-urlbar-background-transparent: var(--omazen-background-light)' \
  "$CHROME_CSS" || fail "expanded URL bar background"
grep -Fq -- '#urlbar:is([focused="true"], [breakout-extend]) .urlbar-background' \
  "$CHROME_CSS" || fail "focused URL bar outline"
grep -Fq -- ':not([zen-compact-mode="true"]) #navigator-toolbox' \
  "$CHROME_CSS" || fail "non-compact toolbox palette"
grep -Fq -- '[zen-compact-mode="true"] .zen-toolbar-background' \
  "$CHROME_CSS" || fail "compact rounded background palette"
grep -Fq -- '--zen-navigator-toolbox-background: transparent' \
  "$CHROME_CSS" || fail "compact rectangular toolbox transparency"
if grep -Fxq -- '  #navigator-toolbox,' "$CHROME_CSS"; then
  fail "compact rectangular toolbox must remain transparent"
fi
if grep -A3 -F -- '[zen-compact-mode="true"] .zen-toolbar-background {' \
  "$CHROME_CSS" | grep -Eq -- '(box-shadow|outline)'; then
  fail "compact rounded background must retain Zen's native frame and shadow"
fi
if grep -Fq -- '#urlbar-background' "$CHROME_CSS"; then
  fail "obsolete URL bar background ID selector"
fi
if grep -Fq -- 'zen-workspace[active]' "$CHROME_CSS"; then
  fail "active workspace container must not receive selection background"
fi
if grep -Fq -- '.zen-current-workspace-indicator' "$CHROME_CSS"; then
  fail "workspace indicator must retain native padding and background"
fi
if sed -n '/:is(/,/)/p' "$CHROME_CSS" | grep -Fxq '  input'; then
  fail "generic input selector must not repaint the URL text field"
fi
grep -Fq -- ':is(menupopup, panel) :is(menu, menuitem)[_moz-menuactive]:not([disabled])' \
  "$CHROME_CSS" || fail "context menu hover selector"
grep -A3 -F -- ':is(menupopup, panel) :is(menu, menuitem)[_moz-menuactive]:not([disabled])' \
  "$CHROME_CSS" | grep -Fq -- 'background-color: var(--omazen-selection)' || \
  fail "context menu hover background palette"
grep -A4 -F -- ':is(menupopup, panel) :is(menu, menuitem)[_moz-menuactive]:not([disabled])' \
  "$CHROME_CSS" | grep -Fq -- 'color: var(--omazen-foreground)' || \
  fail "context menu hover text palette"
grep -Fq -- '--background-color-canvas: var(--omazen-background)' \
  "$CONTENT_CSS" || fail "Settings canvas palette"
grep -Fq -- '--input-text-background-color: var(--omazen-background-dark)' \
  "$CONTENT_CSS" || fail "Settings search palette"
grep -Fq -- '--theme-bg-color: var(--omazen-background-light)' \
  "$CONTENT_CSS" || fail "managed notice palette"
grep -Fq -- '--checkbox-background-color-checked: var(--omazen-accent)' \
  "$CONTENT_CSS" || fail "Settings radio palette"
grep -Fq -- '--toggle-background-color-pressed: var(--omazen-accent)' \
  "$CONTENT_CSS" || fail "Settings toggle palette"
grep -Fq -- '--select-text-color: var(--omazen-foreground)' \
  "$CONTENT_CSS" || fail "Settings selector text palette"
grep -Fq -- 'scrollbar-color: var(--omazen-scrollbar-thumb) var(--omazen-scrollbar-track)' \
  "$CONTENT_CSS" || fail "internal page scrollbar palette"
grep -Fq -- 'scrollbar-color: var(--omazen-scrollbar-thumb) var(--omazen-scrollbar-track)' \
  "$CHROME_CSS" || fail "browser chrome scrollbar palette"
# shellcheck disable=SC2016 # Backticks are literal documentation text.
grep -Fq -- 'solely to set `scrollbar-color`' \
  "$PROJECT_ROOT/docs/architecture.md" || fail "web scrollbar architecture documentation"
# shellcheck disable=SC2016 # Backticks are literal documentation text.
grep -Fq -- 'can set only `scrollbar-color`' \
  "$PROJECT_ROOT/docs/security.md" || fail "web scrollbar security boundary documentation"
grep -Fq -- 'only vertical and horizontal scrollbar colors' \
  "$PROJECT_ROOT/docs/compatibility.md" || fail "web scrollbar compatibility boundary documentation"
grep -Fq -- '--link-color: var(--omazen-accent)' \
  "$CONTENT_CSS" || fail "Settings link token palette"
grep -Fq -- '::part(support-link)' \
  "$CONTENT_CSS" || fail "Settings support link palette"
grep -Fq -- '#zenCKSResetButton {' \
  "$CONTENT_CSS" || fail "Keyboard Shortcuts reset button palette"
grep -Fq -- '.zenCKSOption > .zenCKSOption-label {' \
  "$CONTENT_CSS" || fail "Keyboard Shortcuts label palette"
grep -Fq -- '#zenCKSOption-wrapper > [data-group] {' \
  "$CONTENT_CSS" || fail "Keyboard Shortcuts group palette"
grep -Fq -- '.zenCKSOption-input.zenCKSOption-input-editing {' \
  "$CONTENT_CSS" || fail "Keyboard Shortcuts editing palette"
grep -Fq -- '#zenMarketplaceGroup button {' \
  "$CONTENT_CSS" || fail "Zen Mods action palette"
grep -Fq -- '#zenThemeMarketplaceLink:is(:hover, :focus-visible)' \
  "$CONTENT_CSS" || fail "Zen Mods store link hover palette"
grep -Fq -- '#zenThemeMarketplaceLink:hover:active' \
  "$CONTENT_CSS" || fail "Zen Mods store link active palette"
grep -Fq -- '.zenThemeMarketplaceItem {' \
  "$CONTENT_CSS" || fail "Zen Mods card palette"
grep -Fq -- '.zenThemeMarketplaceItem > dialog {' \
  "$CONTENT_CSS" || fail "Zen Mods dialog palette"
grep -Fq -- '#zenThemeMarketplaceUpdatesFailure,' \
  "$CONTENT_CSS" || fail "Zen Mods status palette"
grep -Fq -- '"about:logins"' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Passwords WindowActor match"
grep -Fq -- 'chrome://browser/content/aboutlogins/aboutLogins.html' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Passwords redirected document match"
grep -Fq -- ':has(login-list) login-list' \
  "$CONTENT_CSS" || fail "Passwords list palette"
grep -Fq -- '--omazen-secondary-text: color-mix(in srgb, var(--omazen-foreground-muted) 40%, var(--omazen-foreground))' \
  "$CONTENT_CSS" || fail "readable secondary text role"
grep -Fq -- '--button-text-color-ghost: var(--omazen-action-text)' \
  "$CONTENT_CSS" || fail "enabled ghost action text palette"
grep -Fq -- '--omazen-accent-foreground: var(--omazen-background-dark)' \
  "$CONTENT_CSS" || fail "accent foreground fallback token"
grep -Fq -- '--button-text-color-primary: var(--omazen-accent-foreground)' \
  "$CONTENT_CSS" || fail "primary button contrast token"
grep -Fq -- '--in-content-primary-button-text-color: var(--omazen-accent-foreground)' \
  "$CONTENT_CSS" || fail "in-content primary button contrast token"
grep -Fq -- '--button-text-color-menu-active: var(--omazen-action-text)' \
  "$CONTENT_CSS" || fail "active menu action text palette"
grep -Fq -- '--box-button-text-color-disabled: var(--omazen-disabled-text)' \
  "$CONTENT_CSS" || fail "disabled box action text palette"
grep -Fq -- '"about:translations"' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Translations WindowActor match"
grep -Fq -- 'chrome://global/content/translations/about-translations.html' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Translations redirected document match"
grep -Fq -- '"about:debugging"' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Remote Debugging WindowActor match"
grep -Fq -- '"chrome://devtools/content/*"' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Developer tools WindowActor scope"
grep -Fq -- '"devtools:toolbox": DEVTOOLS_TOOLBOX_URI' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Developer toolbox window allowlist"
grep -Fq -- 'chrome://global/content/print.html' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Print internal document scope"
grep -Fq -- '--theme-body-background: var(--omazen-background)' \
  "$CONTENT_CSS" || fail "Developer tools surface palette"
grep -Fq -- '#customization-container' \
  "$CHROME_CSS" || fail "Customize Toolbar palette"
grep -Fq -- '--message-bar-background-color: var(--omazen-background-dark)' \
  "$CHROME_CSS" || fail "notification background palette"
grep -Fq -- '--message-bar-text-color: var(--omazen-foreground)' \
  "$CHROME_CSS" || fail "notification text palette"
grep -Fq -- '#aboutDialogContainer #bottomBox' \
  "$CHROME_CSS" || fail "About Zen surface palette"
grep -Fq -- '#aboutDialogContainer button' \
  "$CHROME_CSS" || fail "About Zen button palette"
grep -Fq -- 'notification-message .notification-button.primary' \
  "$CHROME_CSS" || fail "notification primary button palette"
grep -A4 -F -- 'notification-message .notification-button.primary {' \
  "$CHROME_CSS" | grep -Fq -- 'color: var(--omazen-accent-foreground)' || \
  fail "notification primary button contrast token"
grep -Fq -- 'chrome://browser/content/spotlight.html' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Spotlight WindowActor match"
grep -Fq -- ':root#places[data-omazen-enabled="true"] #placesList' \
  "$CHROME_CSS" || fail "Library navigation palette"
grep -Fq -- 'treechildren::-moz-tree-row(selected)' \
  "$CHROME_CSS" || fail "Library tree selection palette"
grep -Fq -- '#downloadsListBox > richlistitem[selected]' \
  "$CHROME_CSS" || fail "Library downloads palette"
grep -Fq -- 'chrome://global/content/commonDialog.xhtml' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "common dialog WindowActor match"
grep -Fq -- 'window.gDialogBox?.dialog?._frame' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Spotlight dialog frame discovery"
grep -Fq -- 'tabDialogBox?._tabDialogManager?._topDialog?._frame' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "tab Spotlight dialog frame discovery"
grep -Fq -- 'applyToInternalDialogFrame(dialogFrame, palette, enabled)' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "direct internal dialog palette application"
grep -Fq -- '!uri.startsWith(SPOTLIGHT_URI) && !uri.startsWith(COMMON_DIALOG_URI)' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "internal dialog URI boundary"
grep -Fq -- 'body[data-page="spotlight"]' \
  "$CONTENT_CSS" || fail "Spotlight surface palette"
grep -Fq -- '#commonDialog::part(omazen-primary-button)' \
  "$CONTENT_CSS" || fail "common dialog primary button palette"
grep -A4 -F -- '#commonDialog::part(omazen-primary-button) {' \
  "$CONTENT_CSS" | grep -Fq -- 'color: var(--omazen-accent-foreground)' || \
  fail "common dialog primary button contrast token"
grep -Fq -- '--button-text-color-primary: var(--omazen-accent-foreground)' \
  "$CONTENT_CSS" || fail "Spotlight primary button contrast"
pass "setup installs the isolated runtime and maps Quattro colors"

rm -f -- "$FAKE_HOOKS/theme-set.d/theme-set"
run_external_omazen setup >/dev/null
assert_absent "$FAKE_HOOKS/theme-set.d/theme-set"
run_external_omazen doctor >/dev/null
assert_file "$FAKE_STATE/provider-mode"
grep -Fqx '1' "$FAKE_STATE/provider-mode" || fail "external provider mode was not persisted"
assert_file "$FAKE_STATE/active-colors"
grep -Fqx "$FAKE_COLORS" "$FAKE_STATE/active-colors" || fail "external palette source was not persisted"
persisted_external_doctor=$(run_persisted_omazen doctor)
grep -Fq '[PASS] external palette provider mode (Omarchy hook not required)' <<<"$persisted_external_doctor" || \
  fail "doctor did not restore the persisted external provider mode"
grep -Fq "[PASS] active palette source: $FAKE_COLORS" <<<"$persisted_external_doctor" || \
  fail "doctor did not restore the persisted external palette source"
persisted_external_sync=$(run_persisted_omazen sync)
grep -Fq 'Palette synchronized atomically' <<<"$persisted_external_sync" || \
  fail "sync did not use the persisted external palette source"
persisted_external_json=$(run_persisted_omazen doctor --json)
printf '%s\n' "$persisted_external_json" | node -e '
  const fs = require("node:fs");
  const report = JSON.parse(fs.readFileSync(0, "utf8"));
  if (!report.ok || report.provider !== "external") process.exit(1);
' || fail "doctor JSON did not report the persisted external provider"
if OMAZEN_SKIP_THEME_HOOK=invalid run_omazen status >/dev/null 2>&1; then
  fail "invalid external palette mode was accepted"
fi
pass "external palette providers can skip the Omarchy theme hook"

MISSING_FX_UTIL="$FAKE_PROFILE/chrome/utils/utils.sys.mjs"
rm -f -- "$MISSING_FX_UTIL"
if run_omazen doctor >/dev/null 2>&1; then
  fail "doctor accepted a partial fx-autoconfig profile runtime"
fi
run_omazen setup >/dev/null
assert_file "$MISSING_FX_UTIL"
assert_same_hash \
  "$MISSING_FX_UTIL" \
  "$PROJECT_ROOT/vendor/fx-autoconfig/profile/chrome/utils/utils.sys.mjs"
run_omazen doctor >/dev/null
pass "setup repairs an owned partial fx-autoconfig profile runtime"

LEGACY_STYLE="$FAKE_PROFILE/chrome/JS/Omazen/omazen-chrome.css"
LEGACY_CONTENT_STYLE="$FAKE_PROFILE/chrome/JS/Omazen/omazen-content.css"
FOREIGN_STYLE="$FAKE_PROFILE/chrome/JS/Omazen/omazen-chrome-v9.9.9.css"
printf 'owned legacy style\n' >"$LEGACY_STYLE"
printf '%s|%s\n' "$LEGACY_STYLE" "$(sha256sum "$LEGACY_STYLE" | awk '{print $1}')" \
  >>"$FAKE_STATE/owned/profile-files"
printf 'owned legacy content style\n' >"$LEGACY_CONTENT_STYLE"
printf '%s|%s\n' "$LEGACY_CONTENT_STYLE" "$(sha256sum "$LEGACY_CONTENT_STYLE" | awk '{print $1}')" \
  >>"$FAKE_STATE/owned/profile-files"
printf 'foreign style\n' >"$FOREIGN_STYLE"
run_omazen setup >/dev/null
assert_absent "$LEGACY_STYLE"
assert_absent "$LEGACY_CONTENT_STYLE"
assert_file "$FOREIGN_STYLE"
assert_same_hash "$FAKE_PROFILE/chrome/userChrome.css" "$TEST_ROOT/userChrome.before"
assert_same_hash "$FAKE_PROFILE/user.js" "$TEST_ROOT/user.before"
run_omazen doctor >/dev/null
pass "setup is idempotent, cleans owned legacy styles, and preserves user files"

INSTALLED_BRIDGE="$FAKE_PROFILE/chrome/JS/omazen-bridge.uc.js"
printf '\n// tampered\n' >>"$INSTALLED_BRIDGE"
if doctor_output=$(run_omazen doctor 2>&1); then
  fail "doctor accepted a modified Omazen profile file"
fi
grep -Fq 'profile file omazen-bridge.uc.js is modified or outdated' <<<"$doctor_output" || \
  fail "doctor did not identify modified installed code"
run_omazen setup >/dev/null

chmod 0666 "$INSTALLED_BRIDGE"
if doctor_output=$(run_omazen doctor 2>&1); then
  fail "doctor accepted unsafe installed-file permissions"
fi
grep -Fq 'unsafe group/world write permissions' <<<"$doctor_output" || \
  fail "doctor did not identify unsafe installed-file permissions"
chmod 0644 "$INSTALLED_BRIDGE"

mv "$INSTALLED_BRIDGE" "$TEST_ROOT/installed-bridge.before"
ln -s "$PROJECT_ROOT/zen/omazen-bridge.uc.js" "$INSTALLED_BRIDGE"
if doctor_output=$(run_omazen doctor 2>&1); then
  fail "doctor accepted a symlinked Omazen profile file"
fi
grep -Fq 'profile file omazen-bridge.uc.js is a symbolic link' <<<"$doctor_output" || \
  fail "doctor did not identify symlinked installed code"
rm -f -- "$INSTALLED_BRIDGE"
mv "$TEST_ROOT/installed-bridge.before" "$INSTALLED_BRIDGE"

cp "$FAKE_COLORS" "$TEST_ROOT/colors.doctor-before"
sed -i 's/accent = "#112233"/accent = "#abcdef"/' "$FAKE_COLORS"
if doctor_output=$(run_omazen doctor 2>&1); then
  fail "doctor accepted a stale normalized palette"
fi
grep -Fq 'normalized palette is missing, invalid, or stale' <<<"$doctor_output" || \
  fail "doctor did not identify the stale normalized palette"
grep -Fq 'accent mismatch:' <<<"$doctor_output" || \
  fail "doctor did not explain the stale palette mismatch"
doctor_json=$(run_omazen doctor --json || true)
printf '%s\n' "$doctor_json" | node -e '
  const fs = require("node:fs");
  const report = JSON.parse(fs.readFileSync(0, "utf8"));
  if (report.ok || report.failures < 1 || !report.checks.some(check => check.status === "FAIL" && check.message.includes("accent mismatch"))) process.exit(1);
' || fail "doctor JSON did not preserve detailed failure diagnostics"
cp "$TEST_ROOT/colors.doctor-before" "$FAKE_COLORS"

printf '%s\n' '2026-08-24T09:59:00.000Z [INFO] BRIDGE_LOADED version=0.9.0' \
  >"$FAKE_STATE/bridge.log"
if doctor_output=$(run_omazen doctor 2>&1); then
  fail "doctor accepted a mismatched loaded bridge version"
fi
grep -Fq "loaded bridge version 0.9.0 does not match Omazen $OMAZEN_VERSION" <<<"$doctor_output" || \
  fail "doctor did not identify the mismatched bridge version"
pass "doctor rejects installation, permission, palette, and bridge drift"

cat >"$FAKE_STATE/bridge.log.1" <<EOF
2026-08-24T10:00:00.000Z [ERROR] historical palette error
2026-08-24T10:01:00.000Z [INFO] BRIDGE_LOADED version=$OMAZEN_VERSION
EOF
cat >"$FAKE_STATE/bridge.log" <<'EOF'
2026-08-24T10:01:00.100Z [INFO] PALETTE_APPLIED accent=#112233 mode=light
2026-08-24T10:01:00.200Z [INFO] CHROME_CSS_APPLIED primary=#112233
EOF
doctor_output=$(run_omazen doctor)
if grep -Fq '[WARN] current bridge error:' <<<"$doctor_output"; then
  fail "doctor reported a historical bridge error after a successful load"
fi
printf '%s\n' '2026-08-24T10:02:00.000Z [ERROR] current palette error' >>"$FAKE_STATE/bridge.log"
if doctor_output=$(run_omazen doctor 2>&1); then
  fail "doctor accepted a current bridge error"
fi
grep -Fq 'current bridge error: 2026-08-24T10:02:00.000Z [ERROR] current palette error' <<<"$doctor_output" || \
  fail "doctor did not report the current bridge error"
pass "doctor reports only a current bridge error"

VALID_COLORS="$TEST_ROOT/colors.before"
cp "$FAKE_COLORS" "$VALID_COLORS"
run_omazen disable >/dev/null
assert_file "$FAKE_STATE/disabled"
printf 'mode = "dark"\n' >"$FAKE_COLORS"
if run_omazen enable >/dev/null 2>&1; then
  fail "enable accepted an invalid palette"
fi
assert_file "$FAKE_STATE/disabled"
if run_omazen setup >/dev/null 2>&1; then
  fail "setup accepted an invalid palette"
fi
assert_file "$FAKE_STATE/disabled"
cp "$VALID_COLORS" "$FAKE_COLORS"
run_omazen enable >/dev/null
assert_absent "$FAKE_STATE/disabled"
pass "enable and setup keep Omazen disabled until palette validation succeeds"

node "$PROJECT_ROOT/tests/js-regressions.mjs" || fail "JavaScript disable cleanup regression"
pass "disable removes Shadow DOM styles and observers"

node "$PROJECT_ROOT/tests/bridge-regressions.mjs" || fail "JavaScript bridge regression"
pass "bridge filters mutations, rotates logs, and cleans up runtime resources"

FOREIGN_PROFILE="$TEST_ROOT/foreign-profile"
FOREIGN_PROFILE_STATE="$TEST_ROOT/foreign-profile-state"
mkdir -p "$FOREIGN_PROFILE/chrome/utils"
printf 'foreign boot with buildScriptActorDefinition\n' >"$FOREIGN_PROFILE/chrome/utils/boot.sys.mjs"
printf 'content userscripts foreign\n' >"$FOREIGN_PROFILE/chrome/utils/chrome.manifest"
if OMAZEN_TESTING=1 OMAZEN_SKIP_PACKAGE_CHECK=1 OMAZEN_HOME_DIR="$FAKE_HOME" \
  OMAZEN_STATE_DIR="$FOREIGN_PROFILE_STATE" OMAZEN_PROFILE="$FOREIGN_PROFILE" \
  OMAZEN_ZEN_CONFIG_DIR="$FAKE_CONFIG" OMAZEN_ZEN_PROGRAM_DIR="$FAKE_ZEN" \
  OMAZEN_HOOKS_DIR="$FAKE_HOOKS" OMAZEN_ACTIVE_COLORS="$FAKE_COLORS" \
  "$PROJECT_ROOT/bin/omazen" setup >/dev/null 2>&1; then
  fail "setup repaired an unowned partial fx-autoconfig profile runtime"
fi
grep -Fq 'foreign boot' "$FOREIGN_PROFILE/chrome/utils/boot.sys.mjs" || \
  fail "foreign partial fx-autoconfig runtime was modified"
pass "setup rejects an unowned partial fx-autoconfig profile runtime"

run_omazen uninstall >/dev/null
assert_absent "$FAKE_PROFILE/chrome/JS/omazen-bridge.uc.js"
assert_absent "$FAKE_STATE/bridge.log.1"
assert_absent "$FAKE_ZEN/defaults/pref/omazen-prefs.js"
assert_same_hash "$FAKE_PROFILE/chrome/userChrome.css" "$TEST_ROOT/userChrome.before"
assert_same_hash "$FAKE_PROFILE/user.js" "$TEST_ROOT/user.before"
pass "uninstall removes owned files and preserves pre-existing files"

CONFLICT_ROOT="$TEST_ROOT/conflict-program"
mkdir -p "$CONFLICT_ROOT/defaults/pref"
printf '[App]\nVersion=1.21.15b\n' >"$CONFLICT_ROOT/application.ini"
printf 'foreign autoconfig\n' >"$CONFLICT_ROOT/config.js"
if OMAZEN_TESTING=1 OMAZEN_SKIP_PACKAGE_CHECK=1 OMAZEN_HOME_DIR="$FAKE_HOME" \
  OMAZEN_STATE_DIR="$TEST_ROOT/conflict-state" OMAZEN_ZEN_CONFIG_DIR="$FAKE_CONFIG" \
  OMAZEN_ZEN_PROGRAM_DIR="$CONFLICT_ROOT" OMAZEN_HOOKS_DIR="$FAKE_HOOKS" \
  OMAZEN_ACTIVE_COLORS="$FAKE_COLORS" "$PROJECT_ROOT/bin/omazen" setup >/dev/null 2>&1; then
  fail "foreign autoconfig conflict was overwritten"
fi
grep -Fq 'foreign autoconfig' "$CONFLICT_ROOT/config.js" || fail "foreign config changed"
pass "setup stops on an unowned autoconfig conflict"

FAKE_APP_DATA="$TEST_ROOT/application-data/omazen"
FAKE_APP_BIN="$TEST_ROOT/application-bin"
OMAZEN_HOME_DIR="$FAKE_HOME" \
OMAZEN_DATA_DIR="$FAKE_APP_DATA" \
OMAZEN_LOCAL_BIN_DIR="$FAKE_APP_BIN" \
OMAZEN_INSTALL_NO_SETUP=1 \
  "$PROJECT_ROOT/install.sh" >/dev/null
assert_file "$FAKE_APP_DATA/.omazen-installed"
assert_same_hash "$FAKE_APP_DATA/VERSION" "$PROJECT_ROOT/VERSION"
assert_same_hash "$FAKE_APP_DATA/CHANGELOG.md" "$PROJECT_ROOT/CHANGELOG.md"
[[ -L $FAKE_APP_BIN/omazen ]] || fail "top-level installer command symlink"
[[ $(readlink -f -- "$FAKE_APP_BIN/omazen") == "$FAKE_APP_DATA/bin/omazen" ]] || \
  fail "top-level installer command target"

printf 'pre-update application copy\n' >"$FAKE_APP_DATA/README.md"
printf 'removed in next release\n' >"$FAKE_APP_DATA/obsolete-application-file"
cp "$FAKE_COLORS" "$TEST_ROOT/colors.install-before"
printf 'mode = "invalid"\n' >"$FAKE_COLORS"
if OMAZEN_HOME_DIR="$FAKE_HOME" \
  OMAZEN_DATA_DIR="$FAKE_APP_DATA" \
  OMAZEN_LOCAL_BIN_DIR="$FAKE_APP_BIN" \
  OMAZEN_TESTING=1 \
  OMAZEN_SKIP_PACKAGE_CHECK=1 \
  OMAZEN_STATE_DIR="$TEST_ROOT/application-state" \
  OMAZEN_ZEN_CONFIG_DIR="$FAKE_CONFIG" \
  OMAZEN_ZEN_PROGRAM_DIR="$FAKE_ZEN" \
  OMAZEN_HOOKS_DIR="$FAKE_HOOKS" \
  OMAZEN_ACTIVE_COLORS="$FAKE_COLORS" \
    "$PROJECT_ROOT/install.sh" >/dev/null 2>&1; then
  fail "top-level installer activated staging after setup failure"
fi
grep -Fq 'pre-update application copy' "$FAKE_APP_DATA/README.md" || \
  fail "failed staged update replaced the active application"
assert_file "$FAKE_APP_DATA/obsolete-application-file"
if find "$TEST_ROOT/application-data" -maxdepth 1 -type d -name 'omazen.staging.*' | grep -q .; then
  fail "failed staged update left a staging directory"
fi
cp "$TEST_ROOT/colors.install-before" "$FAKE_COLORS"

OMAZEN_HOME_DIR="$FAKE_HOME" \
OMAZEN_DATA_DIR="$FAKE_APP_DATA" \
OMAZEN_LOCAL_BIN_DIR="$FAKE_APP_BIN" \
OMAZEN_INSTALL_NO_SETUP=1 \
  "$PROJECT_ROOT/install.sh" >/dev/null
assert_same_hash "$FAKE_APP_DATA/README.md" "$PROJECT_ROOT/README.md"
assert_absent "$FAKE_APP_DATA/obsolete-application-file"
mapfile -t APP_BACKUPS < <(
  find "$TEST_ROOT/application-data" -maxdepth 1 -type d -name 'omazen.backup.*' -print
)
(( ${#APP_BACKUPS[@]} == 1 )) || fail "top-level update backup count"
grep -Fq 'pre-update application copy' "${APP_BACKUPS[0]}/README.md" || \
  fail "top-level update backup contents"

OMAZEN_HOME_DIR="$FAKE_HOME" \
OMAZEN_DATA_DIR="$FAKE_APP_DATA" \
OMAZEN_LOCAL_BIN_DIR="$FAKE_APP_BIN" \
OMAZEN_TESTING=1 \
OMAZEN_STATE_DIR="$TEST_ROOT/application-state" \
OMAZEN_ZEN_CONFIG_DIR="$FAKE_CONFIG" \
OMAZEN_ZEN_PROGRAM_DIR="$FAKE_ZEN" \
OMAZEN_HOOKS_DIR="$FAKE_HOOKS" \
OMAZEN_ACTIVE_COLORS="$FAKE_COLORS" \
  "$FAKE_APP_DATA/uninstall.sh" >/dev/null
assert_absent "$FAKE_APP_DATA"
assert_absent "$FAKE_APP_BIN/omazen"
pass "staged install, failed-update recovery, backup, and uninstall are reversible"

printf '1..12\n'
