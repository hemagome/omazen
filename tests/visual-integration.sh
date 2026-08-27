#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
RELEASE_VERSION=$(<"$PROJECT_ROOT/VERSION")
TEST_ROOT=$(mktemp -d /tmp/omazen-visual-integration.XXXXXX)
OUTPUT_DIR=${OMAZEN_VISUAL_OUTPUT_DIR:-"$TEST_ROOT/output"}
PROFILE="$TEST_ROOT/profile"
STATE_HOME="$TEST_ROOT/state-home"
STATE_DIR="$STATE_HOME/omazen"
BRIDGE_LOG="$STATE_DIR/bridge.log"
COLORS_FILE="$TEST_ROOT/colors.toml"
REPORT="$TEST_ROOT/report.txt"
LAUNCHER_PID=0
BROWSER_PID=0

cleanup() {
  if (( BROWSER_PID > 0 )) && kill -0 "$BROWSER_PID" 2>/dev/null; then
    kill "$BROWSER_PID" 2>/dev/null || true
  fi
  if (( LAUNCHER_PID > 0 )) && kill -0 "$LAUNCHER_PID" 2>/dev/null; then
    kill "$LAUNCHER_PID" 2>/dev/null || true
  fi
  case "$TEST_ROOT" in
    /tmp/omazen-visual-integration.*)
      if [[ ${OMAZEN_KEEP_VISUAL_OUTPUT:-0} == 1 ]]; then
        printf 'visual integration artifacts: %s\n' "$TEST_ROOT"
      else
        rm -rf -- "$TEST_ROOT"
      fi
      ;;
  esac
}
trap cleanup EXIT

fail() {
  printf 'not ok - visual integration: %s\n' "$*" >&2
  if [[ -f $TEST_ROOT/zen.log ]]; then
    sed -n '1,160p' "$TEST_ROOT/zen.log" >&2
  fi
  if [[ -f $BRIDGE_LOG ]]; then
    sed -n '1,160p' "$BRIDGE_LOG" >&2
  fi
  exit 1
}

pass() {
  printf 'ok - visual integration: %s\n' "$*"
}

skip() {
  printf 'ok - visual integration: skipped (%s)\n' "$*"
  exit 0
}

if [[ ${OMAZEN_SKIP_VISUAL_INTEGRATION:-0} == 1 ]]; then
  skip "OMAZEN_SKIP_VISUAL_INTEGRATION=1"
fi

command -v zen-browser >/dev/null 2>&1 || skip "zen-browser is required"
command -v grim >/dev/null 2>&1 || skip "grim is required for Wayland window capture"
command -v hyprctl >/dev/null 2>&1 || skip "hyprctl is required for window geometry"
command -v jq >/dev/null 2>&1 || skip "jq is required for Hyprland window discovery"
if command -v magick >/dev/null 2>&1; then
  IMAGE_MAGICK=magick
elif command -v convert >/dev/null 2>&1 && command -v identify >/dev/null 2>&1 && command -v compare >/dev/null 2>&1; then
  IMAGE_MAGICK=legacy
else
  skip "ImageMagick magick or legacy convert/identify/compare is required"
fi
[[ -n ${WAYLAND_DISPLAY:-} ]] || skip "WAYLAND_DISPLAY is not set"

ZEN_LAUNCHER=$(command -v zen-browser)
ZEN_BIN=$(readlink -f -- "$ZEN_LAUNCHER")
if [[ -f $ZEN_LAUNCHER ]]; then
  launcher_target=$(awk '$1 == "exec" { print $2; exit }' "$ZEN_LAUNCHER")
  if [[ -n ${launcher_target:-} ]]; then
    ZEN_BIN=$(readlink -f -- "$launcher_target")
  fi
fi
ZEN_PROGRAM_DIR=$(dirname -- "$ZEN_BIN")
[[ -f $ZEN_PROGRAM_DIR/config.js ]] || \
  fail "installed Zen program loader is missing: $ZEN_PROGRAM_DIR/config.js"
[[ -f $ZEN_PROGRAM_DIR/defaults/pref/config-prefs.js ]] || \
  fail "installed Zen autoconfig preference is missing"

mkdir -p "$OUTPUT_DIR" "$PROFILE/chrome/JS/Omazen" "$PROFILE/chrome/utils" "$STATE_DIR"

# Keep the browser profile disposable, but use the production fx-autoconfig
# runtime and the same program-level loader as the installed Zen package.
cp -- "$PROJECT_ROOT/vendor/fx-autoconfig/profile/chrome/utils/boot.sys.mjs" \
  "$PROJECT_ROOT/vendor/fx-autoconfig/profile/chrome/utils/chrome.manifest" \
  "$PROJECT_ROOT/vendor/fx-autoconfig/profile/chrome/utils/fs.sys.mjs" \
  "$PROJECT_ROOT/vendor/fx-autoconfig/profile/chrome/utils/module_loader.mjs" \
  "$PROJECT_ROOT/vendor/fx-autoconfig/profile/chrome/utils/uc_api.sys.mjs" \
  "$PROJECT_ROOT/vendor/fx-autoconfig/profile/chrome/utils/utils.sys.mjs" \
  "$PROFILE/chrome/utils/"
cp -- "$PROJECT_ROOT/zen/omazen-bridge.uc.js" "$PROFILE/chrome/JS/"
cp -- "$PROJECT_ROOT/zen/Omazen/OmazenParent.sys.mjs" \
  "$PROJECT_ROOT/zen/Omazen/OmazenChild.sys.mjs" \
  "$PROJECT_ROOT/zen/Omazen/OmazenPalette.sys.mjs" \
  "$PROJECT_ROOT/zen/Omazen/OmazenWatcher.sys.mjs" \
  "$PROFILE/chrome/JS/Omazen/"
cp -- "$PROJECT_ROOT/zen/Omazen/omazen-chrome.css" \
  "$PROFILE/chrome/JS/Omazen/omazen-chrome-v${RELEASE_VERSION}.css"
cp -- "$PROJECT_ROOT/zen/Omazen/omazen-content.css" \
  "$PROFILE/chrome/JS/Omazen/omazen-content-v${RELEASE_VERSION}.css"
cat >"$PROFILE/chrome/JS/visual-control.uc.js" <<'EOF'
// ==UserScript==
// @name Omazen visual integration control
// @description Opens real Zen Settings after the disposable profile bootstrap.
// @include main
// @loadOrder 100
// ==/UserScript==
(() => {
  const markerPath = Services.env.get("OMAZEN_VISUAL_SETTINGS_MARKER");
  let navigated = false;

  function markReady() {
    if (!markerPath) return;
    const file = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
    file.initWithPath(markerPath);
    const stream = Cc["@mozilla.org/network/file-output-stream;1"].createInstance(
      Ci.nsIFileOutputStream,
    );
    stream.init(file, 0x02 | 0x08 | 0x20, 0o600, 0);
    stream.write("ready\n", 6);
    stream.close();
  }

  function ensureSettings() {
    document.getElementById("zen-welcome")?.remove();
    document.documentElement.removeAttribute("zen-welcome-stage");
    const browser = window.gBrowser?.selectedBrowser;
    if (!browser) {
      window.setTimeout(ensureSettings, 100);
      return;
    }
    if (!navigated && browser.currentURI?.spec !== "about:preferences") {
      navigated = true;
      window.gBrowser.addTab("about:preferences", {
        inBackground: false,
        triggeringPrincipal: Services.scriptSecurityManager.getSystemPrincipal(),
      });
    }
    if (browser.currentURI?.spec === "about:preferences") {
      markReady();
      return;
    }
    window.setTimeout(ensureSettings, 100);
  }

  window.setTimeout(ensureSettings, 750);
})();
EOF
cat >"$PROFILE/user.js" <<'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("zen.welcome-screen.seen", true);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
EOF
# Zen's first-window welcome check runs before it can persist user.js into a
# fresh profile. Seed prefs.js as well so this disposable run opens Settings.
cat >"$PROFILE/prefs.js" <<'EOF'
user_pref("browser.aboutwelcome.enabled", false);
user_pref("zen.welcome-screen.seen", true);
EOF

write_colors() {
  local mode=$1
  local accent=$2
  local selection=$3
  local muted=$4
  local background=$5
  local dark_background=$6
  local lighter_background=$7
  local foreground=$8
  local border=$9

  cat >"$COLORS_FILE" <<EOF
mode = "$mode"
accent = "$accent"
selection = "$selection"
muted = "$muted"
background = "$background"
dark_background = "$dark_background"
lighter_background = "$lighter_background"
foreground = "$foreground"
active_border_color = "$border"
EOF
}

sync_provider() {
  OMAZEN_HOME_DIR="$TEST_ROOT/home" \
  OMAZEN_STATE_DIR="$STATE_DIR" \
  OMAZEN_ACTIVE_COLORS="$COLORS_FILE" \
    "$PROJECT_ROOT/bin/omazen" sync >/dev/null
}

log_lines() {
  [[ -f $BRIDGE_LOG ]] && wc -l <"$BRIDGE_LOG" || printf '0\n'
}

wait_for_log() {
  local marker=$1
  local before=$2
  local start=$((before + 1))
  local attempt
  for ((attempt = 1; attempt <= 120; attempt += 1)); do
    if [[ -f $BRIDGE_LOG ]] && tail -n +"$start" "$BRIDGE_LOG" | grep -Fq -- "$marker"; then
      return 0
    fi
    sleep 0.1
  done
  fail "timed out waiting for bridge event: $marker"
}

find_browser_pid() {
  local profile=$1
  ps -eo pid=,args= | awk -v wanted="$profile" '$0 ~ /zen-bin/ && index($0, wanted) { print $1; exit }'
}

window_geometry() {
  local pid=$1
  hyprctl clients -j 2>/dev/null | jq -r --argjson pid "$pid" '
    .[] | select(.class == "zen" and .pid == $pid and .mapped and .visible and (.hidden | not))
    | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"
  ' | head -n 1
}

capture_window() {
  local name=$1
  local geometry
  geometry=$(window_geometry "$BROWSER_PID")
  [[ $geometry =~ ^[0-9]+,[0-9]+[[:space:]][0-9]+x[0-9]+$ ]] || \
    fail "could not find a visible disposable Zen window"
  grim -g "$geometry" "$OUTPUT_DIR/$name-window.png" || \
    fail "grim could not capture the Zen window ($name)"

  local dimensions width height chrome_height settings_height
  if [[ $IMAGE_MAGICK == magick ]]; then
    dimensions=$(magick identify -format '%w %h' "$OUTPUT_DIR/$name-window.png")
  else
    dimensions=$(identify -format '%w %h' "$OUTPUT_DIR/$name-window.png")
  fi
  read -r width height <<<"$dimensions"
  (( width > 20 && height > 20 )) || fail "invalid capture geometry for $name: $dimensions"
  chrome_height=$((height / 5))
  settings_height=$((height - chrome_height))
  if [[ $IMAGE_MAGICK == magick ]]; then
    magick "$OUTPUT_DIR/$name-window.png" -crop "${width}x${chrome_height}+0+0" +repage \
      "$OUTPUT_DIR/$name-chrome.png"
    magick "$OUTPUT_DIR/$name-window.png" -crop "${width}x${settings_height}+0+${chrome_height}" +repage \
      "$OUTPUT_DIR/$name-settings.png"
  else
    convert "$OUTPUT_DIR/$name-window.png" -crop "${width}x${chrome_height}+0+0" +repage \
      "$OUTPUT_DIR/$name-chrome.png"
    convert "$OUTPUT_DIR/$name-window.png" -crop "${width}x${settings_height}+0+${chrome_height}" +repage \
      "$OUTPUT_DIR/$name-settings.png"
  fi
}

compare_metric() {
  local left=$1
  local right=$2
  local fuzz=$3
  local output
  if [[ $IMAGE_MAGICK == magick ]]; then
    output=$(magick compare -metric AE -fuzz "$fuzz" "$left" "$right" null: 2>&1 || true)
  else
    output=$(compare -metric AE -fuzz "$fuzz" "$left" "$right" null: 2>&1 || true)
  fi
  output=${output%% *}
  local metric
  metric=$(awk -v value="$output" 'BEGIN {
    if (value !~ /^[0-9.eE+-]+$/) exit 1;
    printf "%.0f\n", value + 0;
  }') || fail "ImageMagick returned an invalid comparison metric: $output"
  printf '%s\n' "$metric"
}

assert_different() {
  local left=$1
  local right=$2
  local label=$3
  local dimensions width height total mismatches
  if [[ $IMAGE_MAGICK == magick ]]; then
    dimensions=$(magick identify -format '%w %h' "$left")
  else
    dimensions=$(identify -format '%w %h' "$left")
  fi
  read -r width height <<<"$dimensions"
  total=$((width * height))
  mismatches=$(compare_metric "$left" "$right" '3%')
  (( mismatches > total / 100 )) || fail "$label did not visibly change ($mismatches/$total pixels)"
}

assert_similar() {
  local left=$1
  local right=$2
  local label=$3
  local allowed_percent=$4
  local dimensions width height total mismatches limit
  if [[ $IMAGE_MAGICK == magick ]]; then
    dimensions=$(magick identify -format '%w %h' "$left")
  else
    dimensions=$(identify -format '%w %h' "$left")
  fi
  read -r width height <<<"$dimensions"
  total=$((width * height))
  mismatches=$(compare_metric "$left" "$right" '5%')
  limit=$((total * allowed_percent / 100))
  (( mismatches <= limit )) || fail "$label differs too much ($mismatches/$total pixels, limit $limit)"
}

assert_color_present() {
  local image=$1
  local color=$2
  local label=$3
  local ratio
  if [[ $IMAGE_MAGICK == magick ]]; then
    ratio=$(magick "$image" -fuzz 3% -fill white -opaque "#$color" \
      -fill black +opaque white -colorspace gray -format '%[fx:mean]' info:)
  else
    ratio=$(convert "$image" -fuzz 3% -fill white -opaque "#$color" \
      -fill black +opaque white -colorspace gray -format '%[fx:mean]' info:)
  fi
  awk -v value="$ratio" 'BEGIN { exit !(value >= 0.01) }' || \
    fail "$label does not contain palette color #$color within tolerance"
}

write_colors dark '#ff7a18' '#304050' '#a0b0c0' '#102030' '#081018' '#203040' '#f5eedd' '#506070'
sync_provider
export XDG_STATE_HOME="$STATE_HOME"
export OMAZEN_VISUAL_SETTINGS_MARKER="$TEST_ROOT/settings.ready"

zen-browser --new-instance --profile "$PROFILE" >"$TEST_ROOT/zen.log" 2>&1 &
LAUNCHER_PID=$!

for _ in $(seq 1 120); do
  BROWSER_PID=$(find_browser_pid "$PROFILE")
  if [[ -n $BROWSER_PID ]] && window_geometry "$BROWSER_PID" >/dev/null; then
    break
  fi
  sleep 0.1
done
[[ -n $BROWSER_PID ]] || fail "Zen did not create a window for the disposable profile"
wait_for_log "BRIDGE_LOADED version=$RELEASE_VERSION" 0
wait_for_log 'WATCHER_READY backend=inotify' 0
wait_for_log 'PALETTE_APPLIED accent=#ff7a18 mode=dark' 0
wait_for_log 'CHROME_CSS_APPLIED primary=#ff7a18' 0
for _ in $(seq 1 120); do
  [[ -s $TEST_ROOT/settings.ready ]] && break
  sleep 0.1
done
[[ -s $TEST_ROOT/settings.ready ]] || fail "visual control script did not navigate the disposable window to Settings"
sleep 0.5
capture_window dark
assert_color_present "$OUTPUT_DIR/dark-window.png" '081018' 'dark chrome/settings capture'
assert_color_present "$OUTPUT_DIR/dark-settings.png" '081018' 'dark Settings capture'
pass "real loader, bridge and dark Settings/chrome capture"

before=$(log_lines)
write_colors light '#7a18ff' '#c9b4ff' '#6a5845' '#efe4d2' '#d6c5ad' '#fff7ea' '#241b12' '#8b7355'
sync_provider
wait_for_log 'WATCHER_EVENT leaf=palette.json events=MOVED_TO' "$before"
wait_for_log 'PALETTE_APPLIED accent=#7a18ff mode=light' "$before"
wait_for_log 'CHROME_CSS_APPLIED primary=#7a18ff' "$before"
sleep 0.5
capture_window light
assert_color_present "$OUTPUT_DIR/light-window.png" 'efe4d2' 'light chrome/settings capture'
assert_color_present "$OUTPUT_DIR/light-settings.png" 'efe4d2' 'light Settings capture'
assert_different "$OUTPUT_DIR/dark-chrome.png" "$OUTPUT_DIR/light-chrome.png" 'dark/light chrome'
assert_different "$OUTPUT_DIR/dark-settings.png" "$OUTPUT_DIR/light-settings.png" 'dark/light Settings'
pass "live palette change from dark to light"

before=$(log_lines)
OMAZEN_HOME_DIR="$TEST_ROOT/home" \
OMAZEN_STATE_DIR="$STATE_DIR" \
OMAZEN_ACTIVE_COLORS="$COLORS_FILE" \
  "$PROJECT_ROOT/bin/omazen" disable >/dev/null
wait_for_log 'WATCHER_EVENT leaf=disabled events=' "$before"
wait_for_log 'DISABLED' "$before"
sleep 0.5
capture_window disabled
assert_different "$OUTPUT_DIR/light-window.png" "$OUTPUT_DIR/disabled-window.png" 'disable/enable baseline'
pass "disable removes Omazen palette from the live window"

before=$(log_lines)
OMAZEN_HOME_DIR="$TEST_ROOT/home" \
OMAZEN_STATE_DIR="$STATE_DIR" \
OMAZEN_ACTIVE_COLORS="$COLORS_FILE" \
  "$PROJECT_ROOT/bin/omazen" enable >/dev/null
wait_for_log 'WATCHER_EVENT leaf=disabled events=DELETE' "$before"
wait_for_log 'PALETTE_APPLIED accent=#7a18ff mode=light' "$before"
sleep 0.5
capture_window reenabled
assert_similar "$OUTPUT_DIR/light-window.png" "$OUTPUT_DIR/reenabled-window.png" 're-enabled light palette' 15
pass "enable reapplies the light palette without restarting Zen"

if (( BROWSER_PID > 0 )) && kill -0 "$BROWSER_PID" 2>/dev/null; then
  kill "$BROWSER_PID" 2>/dev/null || true
fi
wait "$LAUNCHER_PID" 2>/dev/null || true
LAUNCHER_PID=0
BROWSER_PID=0

[[ -f $PROFILE/prefs.js ]] || fail "disposable Zen profile did not persist preferences"
grep -Fq 'user_pref("omazen.enabled", true);' "$PROFILE/prefs.js" || \
  fail "bridge did not persist omazen.enabled in disposable profile"
grep -Fq 'user_pref("omazen.palette.mode", "light");' "$PROFILE/prefs.js" || \
  fail "bridge did not persist the light palette mode in disposable profile"
grep -Fq 'user_pref("omazen.palette.accent", "#7a18ff");' "$PROFILE/prefs.js" || \
  fail "bridge did not persist the light palette accent in disposable profile"
pass "WindowActor-backed Settings state and palette preferences persisted"

printf 'visual integration captures: %s\n' "$OUTPUT_DIR" >"$REPORT"
pass "visual comparison passed with a 3% difference threshold and 15% re-enable tolerance"
