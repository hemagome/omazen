#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
CANDIDATE_BIN=${OMAZEN_CANDIDATE_BIN:-"$PROJECT_ROOT/target/release/omazen-rust"}
MANIFEST="$PROJECT_ROOT/tests/fixtures/cli-contract/v1.4.1/state.sha256"
UPDATE_MANIFEST=${OMAZEN_UPDATE_CONTRACT_MANIFEST:-0}
TEST_ROOT=$(mktemp -d /tmp/omazen-state-contract.XXXXXX)

cleanup() {
  case "$TEST_ROOT" in
    /tmp/omazen-state-contract.*) rm -rf -- "$TEST_ROOT" ;;
  esac
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

mkdir -p "$TEST_ROOT/bin"
cat >"$TEST_ROOT/bin/omarchy" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$OMAZEN_CONTRACT_OMARCHY_LOG"
EOF
chmod +x "$TEST_ROOT/bin/omarchy"

write_valid_colors() {
  cat >"$1" <<'EOF'
mode = "dark"
accent = "#112233"
selection = "#223344"
muted = "#334455"
background = "#111111"
dark_background = "#000000"
lighter_background = "#222222"
foreground = "#eeeeee"
EOF
}

run_one() {
  local binary=$1
  local root=$2
  shift 2
  local status=0
  PATH="$TEST_ROOT/bin:$PATH" \
  OMAZEN_HOME_DIR="$root/home" \
  OMAZEN_STATE_DIR="$root/state" \
  OMAZEN_ACTIVE_COLORS="$root/colors.toml" \
  OMAZEN_SKIP_THEME_HOOK=1 \
  OMAZEN_CONTRACT_OMARCHY_LOG="$root/omarchy.log" \
    "$binary" "$@" >"$root/stdout" 2>"$root/stderr" || status=$?
  sed -i "s|$root|<ROOT>|g" "$root/stdout" "$root/stderr"
  printf '%s\n' "$status" >"$root/status"
  if [[ -f $root/state/palette.json ]]; then
    stat -c '%a' "$root/state/palette.json" >"$root/palette-mode"
  fi
}

expected_hash() {
  local key=$1
  awk -v key="$key" '$2 == key { print $1; found = 1 } END { if (!found) exit 1 }' "$MANIFEST"
}

manifest_line() {
  local key=$1
  local path=$2
  if [[ -e $path ]]; then
    printf '%s %s\n' "$(sha256sum "$path" | awk '{ print $1 }')" "$key"
  else
    printf 'MISSING %s\n' "$key"
  fi
}

verify_artifact() {
  local key=$1
  local path=$2
  local expected actual=MISSING
  expected=$(expected_hash "$key") || fail "missing manifest entry: $key"
  [[ -e $path ]] && actual=$(sha256sum "$path" | awk '{ print $1 }')
  [[ $actual == "$expected" ]] || fail "$key differs from the v1.4.1 contract"
}

run_case() {
  local name=$1
  local preparation=$2
  shift 2
  local candidate="$TEST_ROOT/$name"
  mkdir -p "$candidate"
  write_valid_colors "$candidate/colors.toml"
  case $preparation in
    disabled)
      mkdir -p "$candidate/state"
      : >"$candidate/state/disabled"
      chmod 600 "$candidate/state/disabled"
      ;;
    invalid-disabled)
      mkdir -p "$candidate/state"
      : >"$candidate/state/disabled"
      printf 'mode = "invalid"\n' >"$candidate/colors.toml"
      ;;
  esac
  run_one "$CANDIDATE_BIN" "$candidate" "$@"
  (( UPDATE_MANIFEST == 1 )) && return
  for artifact in stdout stderr status state/palette.json state/disabled omarchy.log palette-mode; do
    verify_artifact "$name/$artifact" "$candidate/$artifact"
  done
  printf 'ok - state parity: %s\n' "$name"
}

run_case disable clean disable
run_case disable-arity clean disable unexpected
run_case enable disabled enable
run_case enable-invalid invalid-disabled enable
run_case enable-arity disabled enable unexpected
run_case set-sync clean set
run_case set-theme clean set 'Theme With Spaces'
run_case set-arity clean set one two

if (( UPDATE_MANIFEST == 1 )); then
  for name in disable disable-arity enable enable-invalid enable-arity set-sync set-theme set-arity; do
    for artifact in stdout stderr status state/palette.json state/disabled omarchy.log palette-mode; do
      manifest_line "$name/$artifact" "$TEST_ROOT/$name/$artifact"
    done
  done
  exit 0
fi

printf '1..8\n'
