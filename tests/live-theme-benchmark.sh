#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

BENCH_HOME_DIR=${OMAZEN_HOME_DIR:-$HOME}
STATE_DIR=${OMAZEN_STATE_DIR:-"${XDG_STATE_HOME:-$BENCH_HOME_DIR/.local/state}/omazen"}
BRIDGE_LOG="$STATE_DIR/bridge.log"
BRIDGE_LOG_ARCHIVE="$STATE_DIR/bridge.log.1"
SECONDARY_THEME=""
OUTPUT_DIR=""
CYCLES=3
TIMEOUT_SECONDS=8
ORIGINAL_THEME=$(omarchy theme current)
TEMP_DIR=""

usage() {
  cat <<'EOF'
Usage: tests/live-theme-benchmark.sh --secondary-theme THEME --output-dir DIR [options]

Options:
  --cycles N       Complete secondary/original cycles (default: 3)
  --timeout SEC    Event timeout per theme change (default: 8)
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

while (( $# > 0 )); do
  case $1 in
    --secondary-theme) SECONDARY_THEME=${2:-}; shift 2 ;;
    --output-dir) OUTPUT_DIR=${2:-}; shift 2 ;;
    --cycles) CYCLES=${2:-}; shift 2 ;;
    --timeout) TIMEOUT_SECONDS=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

[[ -n $SECONDARY_THEME ]] || die "--secondary-theme is required"
[[ -n $OUTPUT_DIR ]] || die "--output-dir is required"
[[ $CYCLES =~ ^[1-9][0-9]*$ ]] || die "--cycles must be a positive integer"
[[ $TIMEOUT_SECONDS =~ ^[1-9][0-9]*$ ]] || die "--timeout must be a positive integer"
[[ -f $BRIDGE_LOG ]] || die "bridge log is missing: $BRIDGE_LOG"
omarchy theme list | grep -Fxq "$SECONDARY_THEME" || die "theme is unavailable: $SECONDARY_THEME"
[[ $SECONDARY_THEME != "$ORIGINAL_THEME" ]] || die "secondary theme matches the original theme"

mkdir -p -- "$OUTPUT_DIR"
OUTPUT_DIR=$(cd -- "$OUTPUT_DIR" && pwd -P)
SAMPLES_FILE="$OUTPUT_DIR/samples.csv"
ENVIRONMENT_FILE="$OUTPUT_DIR/environment.json"
TEMP_DIR=$(mktemp -d /tmp/omazen-theme-benchmark.XXXXXX)

cleanup() {
  local status=$?
  if [[ $(omarchy theme current) != "$ORIGINAL_THEME" ]]; then
    printf 'Restoring original theme after benchmark: %s\n' "$ORIGINAL_THEME" >&2
    omarchy theme set "$ORIGINAL_THEME" >/dev/null || status=1
  fi
  case "$TEMP_DIR" in
    /tmp/omazen-theme-benchmark.*) rm -rf -- "$TEMP_DIR" ;;
  esac
  exit "$status"
}
trap cleanup EXIT

log_size() {
  [[ -f $BRIDGE_LOG ]] && wc -c <"$BRIDGE_LOG" || printf '0\n'
}

read_log_since() {
  local before_bytes=$1
  local current_bytes=$2
  local destination=$3
  if (( current_bytes >= before_bytes )); then
    tail -c "+$((before_bytes + 1))" "$BRIDGE_LOG" >"$destination"
  else
    [[ -f $BRIDGE_LOG_ARCHIVE ]] || return 1
    tail -c "+$((before_bytes + 1))" "$BRIDGE_LOG_ARCHIVE" >"$destination"
    cat "$BRIDGE_LOG" >>"$destination"
  fi
}

line_timestamp_ns() {
  local line=$1
  local timestamp=${line%% \[*}
  date -d "$timestamp" +%s%N
}

delta_ms() {
  awk -v start="$1" -v end="$2" 'BEGIN { printf "%.3f", (end - start) / 1000000 }'
}

wait_for_events() {
  local before_bytes=$1
  local destination=$2
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local current_bytes
  while (( SECONDS < deadline )); do
    current_bytes=$(log_size)
    if (( current_bytes != before_bytes )); then
      read_log_since "$before_bytes" "$current_bytes" "$destination" || return 1
      if grep -Fq 'PALETTE_APPLIED ' "$destination" && grep -Fq 'CHROME_CSS_APPLIED ' "$destination"; then
        sleep 1
        current_bytes=$(log_size)
        read_log_since "$before_bytes" "$current_bytes" "$destination" || return 1
        return 0
      fi
    fi
    sleep 0.02
  done
  return 1
}

windows=$(hyprctl clients -j | jq '[.[] | select((.class | ascii_downcase) == "zen")] | length')
(( windows > 0 )) || die "at least one Zen window is required"

jq -n \
  --arg start_time "$(date -Is)" \
  --arg original_theme "$ORIGINAL_THEME" \
  --arg secondary_theme "$SECONDARY_THEME" \
  --argjson cycles "$CYCLES" \
  --argjson zen_windows "$windows" \
  '{schema_version: 1, start_time: $start_time, original_theme: $original_theme,
    secondary_theme: $secondary_theme, cycles: $cycles, zen_windows: $zen_windows}' \
  >"$ENVIRONMENT_FILE"
printf '%s\n' 'cycle,target,command_ms,trigger_to_palette_ms,trigger_to_css_ms,palette_events,css_events,verified_theme' >"$SAMPLES_FILE"

run_change() {
  local cycle=$1
  local target=$2
  local before_bytes start_ns end_ns lines_file palette_line css_line
  local palette_events css_events current_theme
  before_bytes=$(log_size)
  start_ns=$(date +%s%N)
  omarchy theme set "$target" >/dev/null
  end_ns=$(date +%s%N)
  lines_file="$TEMP_DIR/cycle-$cycle-${target// /-}.log"
  wait_for_events "$before_bytes" "$lines_file" || die "timed out waiting for bridge events after theme: $target"
  palette_line=$(grep -m1 -F 'PALETTE_APPLIED ' "$lines_file")
  css_line=$(grep -m1 -F 'CHROME_CSS_APPLIED ' "$lines_file")
  palette_events=$(grep -c -F 'PALETTE_APPLIED ' "$lines_file" || true)
  css_events=$(grep -c -F 'CHROME_CSS_APPLIED ' "$lines_file" || true)
  current_theme=$(omarchy theme current)
  [[ $current_theme == "$target" ]] || die "theme verification failed: expected $target, found $current_theme"
  printf '%d,%s,%s,%s,%s,%d,%d,%s\n' \
    "$cycle" "${target//,/ }" "$(delta_ms "$start_ns" "$end_ns")" \
    "$(delta_ms "$start_ns" "$(line_timestamp_ns "$palette_line")")" \
    "$(delta_ms "$start_ns" "$(line_timestamp_ns "$css_line")")" \
    "$palette_events" "$css_events" "${current_theme//,/ }" >>"$SAMPLES_FILE"
  printf 'theme cycle %d: %s command=%sms palette_events=%d css_events=%d\n' \
    "$cycle" "$target" "$(delta_ms "$start_ns" "$end_ns")" "$palette_events" "$css_events"
}

for ((cycle = 1; cycle <= CYCLES; cycle += 1)); do
  run_change "$cycle" "$SECONDARY_THEME"
  run_change "$cycle" "$ORIGINAL_THEME"
done

printf 'Theme samples: %s\nEnvironment: %s\n' "$SAMPLES_FILE" "$ENVIRONMENT_FILE"
