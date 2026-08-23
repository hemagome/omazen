#!/bin/bash

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
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

mkdir -p "$FAKE_ZEN/defaults/pref" "$FAKE_PROFILE/chrome" "$(dirname -- "$FAKE_COLORS")"
printf '[App]\nVersion=1.21.15b\n' >"$FAKE_ZEN/application.ini"
printf '[Profile0]\nName=Test\nIsRelative=1\nPath=abc.Test Profile\nDefault=1\n' >"$FAKE_CONFIG/profiles.ini"
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
  "$PROJECT_ROOT/bin/omazen" "$@"
}

run_omazen setup >/dev/null
assert_file "$FAKE_STATE/palette.json"
assert_file "$FAKE_ZEN/config.js"
assert_file "$FAKE_ZEN/defaults/pref/config-prefs.js"
assert_file "$FAKE_ZEN/defaults/pref/omazen-prefs.js"
assert_file "$FAKE_PROFILE/chrome/JS/omazen-bridge.uc.js"
assert_file "$FAKE_PROFILE/chrome/JS/Omazen/OmazenChild.sys.mjs"
assert_file "$FAKE_PROFILE/chrome/JS/Omazen/omazen-chrome-v0.1.11.css"
assert_file "$FAKE_PROFILE/chrome/JS/Omazen/omazen-content-v0.1.11.css"
assert_file "$FAKE_HOOKS/theme-set.d/theme-set"
grep -Fq 'Omazen: 0.1.11' <(run_omazen status) || fail "reported package version"
grep -Fq 'omazen-chrome-v0.1.11.css' "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || \
  fail "chrome stylesheet cache buster"
grep -Fq 'omazen-content-v0.1.11.css' "$PROJECT_ROOT/zen/Omazen/OmazenChild.sys.mjs" || \
  fail "content stylesheet cache buster"
grep -Fq '"mode": "light"' "$FAKE_STATE/palette.json" || fail "palette mode mapping"
grep -Fq '"background_dark": "#eeeeee"' "$FAKE_STATE/palette.json" || fail "palette background mapping"
grep -Fq -- '--zen-urlbar-background-base: var(--omazen-background-light)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "inactive URL bar background"
grep -Fq -- '--lwt-toolbar-field-focus: var(--omazen-background-light)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "focused URL bar background"
grep -Fq -- '--zen-urlbar-background-transparent: var(--omazen-background-light)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "expanded URL bar background"
grep -Fq -- '#urlbar:is([focused="true"], [breakout-extend]) .urlbar-background' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "focused URL bar outline"
if grep -Fq -- '#urlbar-background' "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css"; then
  fail "obsolete URL bar background ID selector"
fi
if grep -Fq -- 'zen-workspace[active]' "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css"; then
  fail "active workspace container must not receive selection background"
fi
if grep -Fq -- '.zen-current-workspace-indicator' "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css"; then
  fail "workspace indicator must retain native padding and background"
fi
if sed -n '/:is(/,/)/p' "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" | grep -Fxq '  input'; then
  fail "generic input selector must not repaint the URL text field"
fi
grep -Fq -- '--background-color-canvas: var(--omazen-background)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Settings canvas palette"
grep -Fq -- '--input-text-background-color: var(--omazen-background-dark)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Settings search palette"
grep -Fq -- '--theme-bg-color: var(--omazen-background-light)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "managed notice palette"
grep -Fq -- '--checkbox-background-color-checked: var(--omazen-accent)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Settings radio palette"
grep -Fq -- '--toggle-background-color-pressed: var(--omazen-accent)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Settings toggle palette"
grep -Fq -- '--select-text-color: var(--omazen-foreground)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Settings selector text palette"
grep -Fq -- 'scrollbar-color: var(--omazen-scrollbar-thumb) var(--omazen-scrollbar-track)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "internal page scrollbar palette"
grep -Fq -- 'scrollbar-color: var(--omazen-scrollbar-thumb) var(--omazen-scrollbar-track)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "browser chrome scrollbar palette"
grep -Fq -- '--omazen-scrollbar-thumb: ${palette.foreground_muted}' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "isolated document scrollbar palette"
grep -Fq -- '@-moz-document url-prefix("http://"), url-prefix("https://"), url-prefix("file://")' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "web page scrollbar scope"
grep -Fq -- 'scrollbar-color: ${palette.foreground_muted} ${palette.background_dark}' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "web page scrollbar palette"
grep -Fq -- '--link-color: var(--omazen-accent)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Settings link token palette"
grep -Fq -- '::part(support-link)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Settings support link palette"
grep -Fq -- 'ensureSecurityPrivacyCardLinks(document)' \
  "$PROJECT_ROOT/zen/Omazen/OmazenChild.sys.mjs" || fail "Privacy card shadow link palette"
grep -Fq -- 'a:hover:active {' \
  "$PROJECT_ROOT/zen/Omazen/OmazenChild.sys.mjs" || fail "Privacy card shadow link interaction palette"
grep -Fq -- '#zenCKSResetButton {' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Keyboard Shortcuts reset button palette"
grep -Fq -- '.zenCKSOption > .zenCKSOption-label {' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Keyboard Shortcuts label palette"
grep -Fq -- '#zenCKSOption-wrapper > [data-group] {' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Keyboard Shortcuts group palette"
grep -Fq -- '.zenCKSOption-input.zenCKSOption-input-editing {' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Keyboard Shortcuts editing palette"
grep -Fq -- '#zenMarketplaceGroup button {' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Zen Mods action palette"
grep -Fq -- '.zenThemeMarketplaceItem {' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Zen Mods card palette"
grep -Fq -- '.zenThemeMarketplaceItem > dialog {' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Zen Mods dialog palette"
grep -Fq -- '#zenThemeMarketplaceUpdatesFailure,' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Zen Mods status palette"
grep -Fq -- '"about:logins"' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Passwords WindowActor match"
grep -Fq -- 'chrome://browser/content/aboutlogins/aboutLogins.html' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Passwords redirected document match"
grep -Fq -- ':has(login-list) login-list' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Passwords list palette"
grep -Fq -- '--button-text-color-ghost: var(--omazen-foreground-muted)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Passwords secondary control palette"
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
grep -Fq -- '@-moz-document url("about:logins")' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "isolated content user-sheet scope"
grep -Fq -- 'styleSheetService.USER_SHEET' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "isolated content user-sheet registration"
grep -Fq -- 'encodeURIComponent(contentPaletteCss(palette))' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "validated content palette encoding"
grep -Fq -- 'chrome://global/content/print.html' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Print internal document scope"
grep -Fq -- '.toggle-group-input:checked + .toggle-group-label' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Print orientation palette"
grep -Fq -- '#open-dialog-link' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Print system-dialog link palette"
grep -Fq -- '--theme-body-background: var(--omazen-background)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Developer tools surface palette"
grep -Fq -- '#customization-container' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "Customize Toolbar palette"
grep -Fq -- '--message-bar-background-color: var(--omazen-background-dark)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "notification background palette"
grep -Fq -- '--message-bar-text-color: var(--omazen-foreground)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "notification text palette"
grep -Fq -- '#aboutDialogContainer #bottomBox' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "About Zen surface palette"
grep -Fq -- '#aboutDialogContainer button' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "About Zen button palette"
grep -Fq -- 'notification-message .notification-button.primary' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "notification primary button palette"
grep -Fq -- 'chrome://browser/content/spotlight.html' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Spotlight WindowActor match"
grep -Fq -- '"Places:Organizer": PLACES_ORGANIZER_URI' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Library window allowlist"
grep -Fq -- 'Services.wm.getEnumerator(windowType)' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "existing auxiliary window synchronization"
grep -Fq -- 'Services.obs.addObserver(auxiliaryWindowObserver, "domwindowopened")' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "late auxiliary window synchronization"
grep -Fq -- ':root#places[data-omazen-enabled="true"] #placesList' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "Library navigation palette"
grep -Fq -- 'treechildren::-moz-tree-row(selected)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "Library tree selection palette"
grep -Fq -- '#downloadsListBox > richlistitem[selected]' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.11.css" || fail "Library downloads palette"
grep -Fq -- 'chrome://global/content/commonDialog.xhtml' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "common dialog WindowActor match"
grep -Fq -- 'document.querySelectorAll("browser")' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "internal dialog browser discovery"
grep -Fq -- 'window.gDialogBox?.dialog?._frame' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "Spotlight dialog frame discovery"
grep -Fq -- 'tabDialogBox?._tabDialogManager?._topDialog?._frame' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "tab Spotlight dialog frame discovery"
grep -Fq -- 'applyToInternalDialogFrame(dialogFrame, palette, enabled)' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "direct internal dialog palette application"
grep -Fq -- '!uri.startsWith(SPOTLIGHT_URI) && !uri.startsWith(COMMON_DIALOG_URI)' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "internal dialog URI boundary"
grep -Fq -- 'new MutationObserver(scheduleInternalPageBroadcast)' \
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || fail "late internal dialog synchronization"
grep -Fq -- 'actorCreated()' \
  "$PROJECT_ROOT/zen/Omazen/OmazenChild.sys.mjs" || fail "actor initial palette application"
grep -Fq -- 'body[data-page="spotlight"]' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Spotlight surface palette"
grep -Fq -- '#commonDialog::part(omazen-primary-button)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "common dialog primary button palette"
grep -Fq -- '--button-text-color-primary: var(--omazen-background-dark)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-content-v0.1.11.css" || fail "Spotlight primary button contrast"
pass "setup installs the isolated runtime and maps Quattro colors"

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

run_omazen disable >/dev/null
assert_file "$FAKE_STATE/disabled"
run_omazen enable >/dev/null
assert_absent "$FAKE_STATE/disabled"
pass "enable and disable use reversible live state"

run_omazen uninstall >/dev/null
assert_absent "$FAKE_PROFILE/chrome/JS/omazen-bridge.uc.js"
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

printf '1..5\n'
