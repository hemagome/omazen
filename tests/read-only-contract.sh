#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
CANDIDATE_BIN=${OMAZEN_CANDIDATE_BIN:-"$PROJECT_ROOT/target/release/omazen-rust"}
RELEASE_VERSION=$(<"$PROJECT_ROOT/VERSION")
BASELINE_VERSION=1.4.1
MANIFEST="$PROJECT_ROOT/tests/fixtures/cli-contract/v1.4.1/read-only.sha256"
UPDATE_MANIFEST=${OMAZEN_UPDATE_CONTRACT_MANIFEST:-0}
TEST_ROOT=$(mktemp -d /tmp/omazen-read-contract.XXXXXX)

cleanup() {
  case "$TEST_ROOT" in
    /tmp/omazen-read-contract.*)
      if [[ ${OMAZEN_KEEP_CONTRACT_OUTPUT:-0} == 1 ]]; then
        printf 'Contract output: %s\n' "$TEST_ROOT"
      else
        rm -rf -- "$TEST_ROOT"
      fi
      ;;
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
  XDG_STATE_HOME="$HOME_ROOT/.local/state" \
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
    -e "s|$TEST_ROOT|<TEST_ROOT>|g" \
    -e "s|${RELEASE_VERSION//./\\.}|$BASELINE_VERSION|g" \
    -e 's/\(age [0-9]+s\)/(age <AGE>s)/g' \
    -e 's/("bridge_last_event_age_seconds": )[0-9]+/\1<AGE>/g' \
    -e 's/("generated_at": ")[^"]+/\1<TIMESTAMP>/g' \
    "$output.stdout" "$output.stderr"
  printf '%s\n' "$status" >"$output.status"
}

run_cli "$CANDIDATE_BIN" "$TEST_ROOT/setup" setup
grep -Fxq '0' "$TEST_ROOT/setup.status" || fail "disposable setup failed"
printf '%s\n' \
  "2026-08-27T00:00:00.000Z [INFO] BRIDGE_LOADED version=$RELEASE_VERSION profile=test" \
  '2026-08-27T00:00:00.001Z [INFO] PALETTE_APPLIED accent=#112233 mode=dark profile=test' \
  '2026-08-27T00:00:00.002Z [INFO] CHROME_CSS_APPLIED primary=#112233 profile=test' \
  '2026-08-27T00:00:00.003Z [INFO] WATCHER_READY backend=inotify profile=test' \
  >"$STATE/bridge.log"

expected_hash() {
  local key=$1
  awk -v key="$key" '$2 == key { print $1; found = 1 } END { if (!found) exit 1 }' "$MANIFEST"
}

manifest_line() {
  local key=$1
  local path=$2
  printf '%s %s\n' "$(sha256sum "$path" | awk '{ print $1 }')" "$key"
}

verify_artifact() {
  local key=$1
  local path=$2
  local expected actual
  expected=$(expected_hash "$key") || fail "missing manifest entry: $key"
  actual=$(sha256sum "$path" | awk '{ print $1 }')
  [[ $actual == "$expected" ]] || fail "$key differs from the v1.4.1 contract"
}

contract_case() {
  local name=$1
  shift
  run_cli "$CANDIDATE_BIN" "$TEST_ROOT/$name" "$@"
  (( UPDATE_MANIFEST == 1 )) && return
  for artifact in stdout stderr status; do
    verify_artifact "$name/$artifact" "$TEST_ROOT/$name.$artifact"
  done
  printf 'ok - read-only parity: %s\n' "$name"
}

contract_case no-arguments
contract_case help help
contract_case help-extra --help ignored
contract_case status status
contract_case status-arity status unexpected
contract_case doctor doctor
contract_case doctor-json doctor --json
contract_case doctor-arity doctor unexpected

cp "$COLORS" "$TEST_ROOT/colors.before"
sed -i 's/accent = "#112233"/accent = "#abcdef"/' "$COLORS"
contract_case doctor-stale doctor
contract_case doctor-stale-json doctor --json
cp "$TEST_ROOT/colors.before" "$COLORS"

touch "$STATE/disabled"
chmod 600 "$STATE/disabled"
contract_case doctor-disabled doctor
rm -f "$STATE/disabled"

printf '2026-08-27T00:00:01.000Z [ERROR] contract failure\n' >>"$STATE/bridge.log"
contract_case doctor-bridge-error doctor
contract_case unknown not-a-command

if (( UPDATE_MANIFEST == 1 )); then
  for name in no-arguments help help-extra status status-arity doctor doctor-json \
    doctor-arity doctor-stale doctor-stale-json doctor-disabled doctor-bridge-error unknown; do
    for artifact in stdout stderr status; do
      manifest_line "$name/$artifact" "$TEST_ROOT/$name.$artifact"
    done
  done
  exit 0
fi

printf '1..13\n'
