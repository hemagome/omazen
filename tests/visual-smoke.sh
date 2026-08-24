#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
FIXTURE="$PROJECT_ROOT/tests/fixtures/visual-smoke.html"
TEST_ROOT=$(mktemp -d /tmp/omazen-visual.XXXXXX)
OUTPUT_DIR=${OMAZEN_VISUAL_OUTPUT_DIR:-"$TEST_ROOT/output"}
OUTPUT="$OUTPUT_DIR/visual-smoke.png"

cleanup() {
  case "$TEST_ROOT" in
    /tmp/omazen-visual.*) rm -rf -- "$TEST_ROOT" ;;
  esac
}
trap cleanup EXIT

fail() {
  printf 'not ok - visual smoke: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'ok - visual smoke: %s\n' "$*"
}

command -v zen-browser >/dev/null 2>&1 || fail "zen-browser is required"
if command -v magick >/dev/null 2>&1; then
  IMAGE_MAGICK=magick
elif command -v convert >/dev/null 2>&1 && command -v identify >/dev/null 2>&1; then
  IMAGE_MAGICK=legacy
else
  fail "ImageMagick magick or legacy convert/identify is required"
fi
[[ -f $FIXTURE ]] || fail "missing fixture: $FIXTURE"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$TEST_ROOT/profile"

# Zen keeps the headless process alive after --screenshot has written the file.
# timeout makes this deterministic while still treating a completed capture as
# success. The profile is disposable and never touches the user's live profile.
set +e
timeout 20s zen-browser \
  --new-instance \
  --headless \
  --profile "$TEST_ROOT/profile" \
  --window-size 1000,768 \
  --screenshot "$OUTPUT" \
  "file://$FIXTURE" \
  >"$TEST_ROOT/zen.log" 2>&1
browser_status=$?
set -e

[[ -s $OUTPUT ]] || {
  sed -n '1,160p' "$TEST_ROOT/zen.log" >&2
  fail "Zen did not produce a screenshot (exit $browser_status)"
}

if [[ $IMAGE_MAGICK == magick ]]; then
  geometry=$(magick identify -format '%m %w %h' "$OUTPUT")
else
  geometry=$(identify -format '%m %w %h' "$OUTPUT")
fi
[[ $geometry == "PNG 1000 768" ]] || \
  fail "unexpected screenshot geometry: $geometry"

pixel() {
  if [[ $IMAGE_MAGICK == magick ]]; then
    magick "$OUTPUT" -format "%[pixel:p{$1,$2}]" info:
  else
    convert "$OUTPUT" -format "%[pixel:p{$1,$2}]" info:
  fi
}

assert_pixel() {
  local name=$1
  local x=$2
  local y=$3
  local expected=$4
  local actual
  actual=$(pixel "$x" "$y")
  [[ $actual == "$expected" ]] || \
    fail "$name at ($x,$y): expected $expected, got $actual"
}

# These are solid interior pixels, away from text, borders and rounded corners.
# They prove the browser painted the CSS values rather than merely accepting
# the selectors in the stylesheet.
assert_pixel "document surface" 10 10 "srgba(16,32,48,1)"
assert_pixel "header surface" 500 70 "srgba(32,48,64,1)"
assert_pixel "card surface" 80 190 "srgba(8,16,24,1)"
assert_pixel "marketplace button" 220 245 "srgba(32,48,64,1)"
assert_pixel "search input" 780 245 "srgba(8,16,24,1)"
assert_pixel "scroll content" 80 570 "srgba(8,16,24,1)"
assert_pixel "scrollbar thumb" 958 450 "srgba(160,176,192,1)"

if [[ ${OMAZEN_KEEP_VISUAL_OUTPUT:-0} != 1 ]]; then
  rm -f -- "$OUTPUT"
fi

pass "Zen rendered production CSS and palette colors into a real screenshot"
