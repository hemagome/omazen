#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
REFERENCE_BIN=${OMAZEN_REFERENCE_BIN:-"$PROJECT_ROOT/bin/omazen"}
CANDIDATE_BIN=${OMAZEN_CANDIDATE_BIN:-$REFERENCE_BIN}
TEST_ROOT=$(mktemp -d /tmp/omazen-read-contract.XXXXXX)

cleanup() {
  case "$TEST_ROOT" in
    /tmp/omazen-read-contract.*) rm -rf -- "$TEST_ROOT" ;;
  esac
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

HOME_ROOT="$TEST_ROOT/home"
STATE="$TEST_ROOT/state"
ZEN_CONFIG="$TEST_ROOT/zen-config"
PROFILE="$ZEN_CONFIG/Profiles/Test Profile"
ZEN_PROGRAM="$TEST_ROOT/zen-program"
HOOKS="$TEST_ROOT/hooks"
COLORS="$TEST_ROOT/colors.toml"
OS_RELEASE="$TEST_ROOT/os-release"
mkdir -p "$PROFILE" "$ZEN_PROGRAM/defaults/pref" "$STATE"
printf '[App]\nVersion=1.21.15b\n' >"$ZEN_PROGRAM/application.ini"
printf '[Profile0]\nName=Test\nIsRelative=1\nPath=Profiles/Test Profile\n' >"$ZEN_CONFIG/profiles.ini"
printf 'NAME="Omarchy"\nPRETTY_NAME="Omarchy"\nID=omarchy\nVERSION_ID="4.0.1"\n' >"$OS_RELEASE"
cat >"$COLORS" <<'EOF'
mode = "dark"
accent = "#112233"
selection = "#223344"
muted = "#334455"
background = "#111111"
dark_background = "#000000"
lighter_background = "#222222"
foreground = "#eeeeee"
EOF

run_cli() {
  local binary=$1
  local output=$2
  shift 2
  local status=0
  OMAZEN_HOME_DIR="$HOME_ROOT" \
  OMAZEN_STATE_DIR="$STATE" \
  OMAZEN_ACTIVE_COLORS="$COLORS" \
  OMAZEN_SKIP_THEME_HOOK=1 \
  OMAZEN_TESTING=1 \
  OMAZEN_SKIP_PACKAGE_CHECK=1 \
  OMAZEN_ZEN_CONFIG_DIR="$ZEN_CONFIG" \
  OMAZEN_ZEN_PROGRAM_DIR="$ZEN_PROGRAM" \
  OMAZEN_HOOKS_DIR="$HOOKS" \
  OMAZEN_OS_RELEASE_FILE="$OS_RELEASE" \
  OMAZEN_ROOT="$PROJECT_ROOT" \
    "$binary" "$@" >"$output.stdout" 2>"$output.stderr" || status=$?
  sed -Ei \
    -e 's/\(age [0-9]+s\)/(age <AGE>s)/g' \
    -e 's/("bridge_last_event_age_seconds": )[0-9]+/\1<AGE>/g' \
    -e 's/("generated_at": ")[^"]+/\1<TIMESTAMP>/g' \
    "$output.stdout" "$output.stderr"
  printf '%s\n' "$status" >"$output.status"
}

run_cli "$REFERENCE_BIN" "$TEST_ROOT/setup" setup
grep -Fxq '0' "$TEST_ROOT/setup.status" || fail "disposable setup failed"
cat >"$STATE/bridge.log" <<'EOF'
2026-08-27T00:00:00.000Z [INFO] BRIDGE_LOADED version=1.4.1 profile=test
2026-08-27T00:00:00.001Z [INFO] PALETTE_APPLIED accent=#112233 mode=dark profile=test
2026-08-27T00:00:00.002Z [INFO] CHROME_CSS_APPLIED primary=#112233 profile=test
2026-08-27T00:00:00.003Z [INFO] WATCHER_READY backend=inotify profile=test
EOF

compare_case() {
  local name=$1
  shift
  run_cli "$REFERENCE_BIN" "$TEST_ROOT/reference-$name" "$@"
  run_cli "$CANDIDATE_BIN" "$TEST_ROOT/candidate-$name" "$@"
  for artifact in stdout stderr status; do
    cmp -s "$TEST_ROOT/reference-$name.$artifact" "$TEST_ROOT/candidate-$name.$artifact" || \
      fail "$name differs in $artifact"
  done
  printf 'ok - read-only parity: %s\n' "$name"
}

compare_case no-arguments
compare_case help help
compare_case help-extra --help ignored
compare_case status status
compare_case status-arity status unexpected
compare_case doctor doctor
compare_case doctor-json doctor --json
compare_case doctor-arity doctor unexpected

cp "$COLORS" "$TEST_ROOT/colors.before"
sed -i 's/accent = "#112233"/accent = "#abcdef"/' "$COLORS"
compare_case doctor-stale doctor
compare_case doctor-stale-json doctor --json
cp "$TEST_ROOT/colors.before" "$COLORS"

touch "$STATE/disabled"
chmod 600 "$STATE/disabled"
compare_case doctor-disabled doctor
rm -f "$STATE/disabled"

printf '2026-08-27T00:00:01.000Z [ERROR] contract failure\n' >>"$STATE/bridge.log"
compare_case doctor-bridge-error doctor
compare_case unknown not-a-command

printf '1..13\n'
