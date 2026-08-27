#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
REFERENCE_BIN=${OMAZEN_REFERENCE_BIN:-"$PROJECT_ROOT/target/release/omazen-rust"}
CANDIDATE_BIN=${OMAZEN_CANDIDATE_BIN:-$REFERENCE_BIN}
TEST_ROOT=$(mktemp -d /tmp/omazen-sync-contract.XXXXXX)

cleanup() {
  case "$TEST_ROOT" in
    /tmp/omazen-sync-contract.*) rm -rf -- "$TEST_ROOT" ;;
  esac
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

write_case() {
  local destination=$1
  local body=$2
  printf '%s' "$body" >"$destination"
}

run_one() {
  local binary=$1
  local case_name=$2
  local colors=$3
  local output_root=$4
  local state="$output_root/state"
  local stdout="$output_root/stdout"
  local stderr="$output_root/stderr"
  local status=0
  mkdir -p "$output_root"
  OMAZEN_HOME_DIR="$output_root/home" \
  OMAZEN_STATE_DIR="$state" \
  OMAZEN_ACTIVE_COLORS="$colors" \
  OMAZEN_SKIP_THEME_HOOK=1 \
    "$binary" sync >"$stdout" 2>"$stderr" || status=$?
  sed -i "s|$output_root|<ROOT>|g" "$stdout" "$stderr"
  printf '%s\n' "$status" >"$output_root/status"
  if [[ -f $state/palette.json ]]; then
    stat -c '%a' "$state" >"$output_root/state-mode"
    stat -c '%a' "$state/palette.json" >"$output_root/palette-mode"
  fi
  printf '%s\n' "$case_name" >"$output_root/case"
}

compare_case() {
  local case_name=$1
  local colors=$2
  local reference="$TEST_ROOT/reference-$case_name"
  local candidate="$TEST_ROOT/candidate-$case_name"
  run_one "$REFERENCE_BIN" "$case_name" "$colors" "$reference"
  run_one "$CANDIDATE_BIN" "$case_name" "$colors" "$candidate"
  for artifact in status stdout stderr state-mode palette-mode; do
    if [[ -e $reference/$artifact || -e $candidate/$artifact ]]; then
      cmp -s "$reference/$artifact" "$candidate/$artifact" || \
        fail "$case_name differs in $artifact"
    fi
  done
  if [[ -e $reference/state/palette.json || -e $candidate/state/palette.json ]]; then
    cmp -s "$reference/state/palette.json" "$candidate/state/palette.json" || \
      fail "$case_name differs in canonical palette bytes"
  fi
  printf 'ok - sync parity: %s\n' "$case_name"
}

VALID="$TEST_ROOT/valid.toml"
write_case "$VALID" $'# comment\r\nmode = "light"\r\naccent = "#AABBCC"\nselection = "#223344"\nmuted = "#334455"\nbackground = "#FEFEFE"\ndark_background = "#EEEEEE"\nlighter_background = "#FFFFFF"\nforeground = "#101010"\nactive_border_color = "invalid"\nignored = bare\naccent = "#112233" # last recognized value wins\n'

VALID_BORDER="$TEST_ROOT/valid-border.toml"
write_case "$VALID_BORDER" $'mode="dark"\naccent="#ABCDEF"\nselection="#223344"\nmuted="#334455"\nbackground="#111111"\ndark_background="#000000"\nlighter_background="#222222"\nforeground="#EEEEEE"\nactive_border_color="#445566"\n'

INVALID_MODE="$TEST_ROOT/invalid-mode.toml"
write_case "$INVALID_MODE" $'mode = "sepia"\naccent = "#112233"\nselection = "#223344"\nmuted = "#334455"\nbackground = "#fefefe"\ndark_background = "#eeeeee"\nlighter_background = "#ffffff"\nforeground = "#101010"\n'

INVALID_COLOR="$TEST_ROOT/invalid-color.toml"
write_case "$INVALID_COLOR" $'mode = "light"\naccent = "#12345"\nselection = "#223344"\nmuted = "#334455"\nbackground = "#fefefe"\ndark_background = "#eeeeee"\nlighter_background = "#ffffff"\nforeground = "#101010"\n'

compare_case valid "$VALID"
compare_case valid-border "$VALID_BORDER"
compare_case invalid-mode "$INVALID_MODE"
compare_case invalid-color "$INVALID_COLOR"
compare_case missing "$TEST_ROOT/missing.toml"

printf '1..5\n'
