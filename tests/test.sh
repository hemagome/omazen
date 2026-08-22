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
assert_file "$FAKE_HOOKS/theme-set.d/theme-set"
grep -Fq 'Omazen: 0.1.2' <(run_omazen status) || fail "reported package version"
grep -Fq 'omazen-chrome-v0.1.2.css' "$PROJECT_ROOT/zen/omazen-bridge.uc.js" || \
  fail "chrome stylesheet cache buster"
grep -Fq '"mode": "light"' "$FAKE_STATE/palette.json" || fail "palette mode mapping"
grep -Fq '"background_dark": "#eeeeee"' "$FAKE_STATE/palette.json" || fail "palette background mapping"
grep -Fq -- '--zen-urlbar-background-base: var(--omazen-background-light)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.2.css" || fail "inactive URL bar background"
grep -Fq -- '--lwt-toolbar-field-focus: var(--omazen-background-light)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.2.css" || fail "focused URL bar background"
grep -Fq -- '--zen-urlbar-background-transparent: var(--omazen-background-light)' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.2.css" || fail "expanded URL bar background"
grep -Fq -- '#urlbar:is([focused="true"], [breakout-extend]) .urlbar-background' \
  "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.2.css" || fail "focused URL bar outline"
if grep -Fq -- '#urlbar-background' "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.2.css"; then
  fail "obsolete URL bar background ID selector"
fi
if grep -Fq -- 'zen-workspace[active]' "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.2.css"; then
  fail "active workspace container must not receive selection background"
fi
if grep -Fq -- '.zen-current-workspace-indicator' "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.2.css"; then
  fail "workspace indicator must retain native padding and background"
fi
if sed -n '/:is(/,/)/p' "$PROJECT_ROOT/zen/Omazen/omazen-chrome-v0.1.2.css" | grep -Fxq '  input'; then
  fail "generic input selector must not repaint the URL text field"
fi
pass "setup installs the isolated runtime and maps Quattro colors"

LEGACY_STYLE="$FAKE_PROFILE/chrome/JS/Omazen/omazen-chrome.css"
FOREIGN_STYLE="$FAKE_PROFILE/chrome/JS/Omazen/omazen-chrome-v9.9.9.css"
printf 'owned legacy style\n' >"$LEGACY_STYLE"
printf '%s|%s\n' "$LEGACY_STYLE" "$(sha256sum "$LEGACY_STYLE" | awk '{print $1}')" \
  >>"$FAKE_STATE/owned/profile-files"
printf 'foreign style\n' >"$FOREIGN_STYLE"
run_omazen setup >/dev/null
assert_absent "$LEGACY_STYLE"
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
