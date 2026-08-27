#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
REFERENCE_BIN=${OMAZEN_REFERENCE_BIN:-"$PROJECT_ROOT/bin/omazen"}
CANDIDATE_BIN=${OMAZEN_CANDIDATE_BIN:-$REFERENCE_BIN}
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
}

compare_artifacts() {
  local name=$1
  local reference=$2
  local candidate=$3
  for artifact in stdout stderr status; do
    cmp -s "$reference/$artifact" "$candidate/$artifact" || fail "$name differs in $artifact"
  done
  for artifact in state/palette.json state/disabled omarchy.log; do
    if [[ -e $reference/$artifact || -e $candidate/$artifact ]]; then
      cmp -s "$reference/$artifact" "$candidate/$artifact" || fail "$name differs in $artifact"
    fi
  done
  if [[ -f $reference/state/palette.json || -f $candidate/state/palette.json ]]; then
    [[ $(stat -c '%a' "$reference/state/palette.json") == \
       $(stat -c '%a' "$candidate/state/palette.json") ]] || fail "$name palette mode differs"
  fi
  printf 'ok - state parity: %s\n' "$name"
}

run_case() {
  local name=$1
  local preparation=$2
  shift 2
  local reference="$TEST_ROOT/reference-$name"
  local candidate="$TEST_ROOT/candidate-$name"
  mkdir -p "$reference" "$candidate"
  write_valid_colors "$reference/colors.toml"
  write_valid_colors "$candidate/colors.toml"
  case $preparation in
    disabled)
      mkdir -p "$reference/state" "$candidate/state"
      : >"$reference/state/disabled"
      : >"$candidate/state/disabled"
      chmod 600 "$reference/state/disabled" "$candidate/state/disabled"
      ;;
    invalid-disabled)
      mkdir -p "$reference/state" "$candidate/state"
      : >"$reference/state/disabled"
      : >"$candidate/state/disabled"
      printf 'mode = "invalid"\n' >"$reference/colors.toml"
      printf 'mode = "invalid"\n' >"$candidate/colors.toml"
      ;;
  esac
  run_one "$REFERENCE_BIN" "$reference" "$@"
  run_one "$CANDIDATE_BIN" "$candidate" "$@"
  compare_artifacts "$name" "$reference" "$candidate"
}

run_case disable clean disable
run_case disable-arity clean disable unexpected
run_case enable disabled enable
run_case enable-invalid invalid-disabled enable
run_case enable-arity disabled enable unexpected
run_case set-sync clean set
run_case set-theme clean set 'Theme With Spaces'
run_case set-arity clean set one two

printf '1..8\n'
