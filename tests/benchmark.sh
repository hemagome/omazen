#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
BENCH_HOME_DIR=${OMAZEN_HOME_DIR:-$HOME}
STATE_DIR=${OMAZEN_STATE_DIR:-"${XDG_STATE_HOME:-$BENCH_HOME_DIR/.local/state}/omazen"}
PALETTE_FILE="$STATE_DIR/palette.json"
BRIDGE_LOG="$STATE_DIR/bridge.log"
BRIDGE_LOG_ARCHIVE="$STATE_DIR/bridge.log.1"
OMAZEN_BIN=${OMAZEN_BIN:-"$PROJECT_ROOT/bin/omazen"}
ITERATIONS=20
TIMEOUT_SECONDS=5
SETTLE_SECONDS=1
MODE=all
OUTPUT_DIR=""
TEMP_DIR=""

usage() {
  cat <<'EOF'
Usage: tests/benchmark.sh [options]

Measure the current Omazen live-update path using the running bridge log.

Options:
  --mode MODE       sync, atomic, or all (default: all)
  --iterations N    Samples per selected mode (default: 20)
  --timeout SEC     Seconds to wait for bridge events (default: 5)
  --settle SEC      Seconds to collect events from other windows (default: 1)
  --output-dir DIR  Write report.md and samples.csv to DIR
  -h, --help        Show this help

The atomic mode rewrites the existing palette with identical contents using
the same atomic rename pattern as lib/palette.sh. It changes file metadata,
but not the visible colors.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

now_ns() {
  date +%s%N
}

delta_ms() {
  awk -v start="$1" -v end="$2" 'BEGIN { delta = (end - start) / 1000000; if (delta < 0) delta = 0; printf "%.3f", delta }'
}

line_timestamp() {
  local line=$1
  local timestamp=${line%% \[*}
  date -d "$timestamp" +%s%N
}

log_size() {
  [[ -f $BRIDGE_LOG ]] || printf '0\n'
  [[ -f $BRIDGE_LOG ]] || return 0
  wc -c <"$BRIDGE_LOG"
}

watcher_backend() {
  local backend pid command_line
  backend=$(awk '
    /\[INFO\] BRIDGE_LOADED / { backend = "starting" }
    /\[INFO\] WATCHER_READY backend=/ {
      backend = "inotify"
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^backend=/) backend = substr($i, 9)
      }
    }
    /\[WARN\] WATCHER_FALLBACK / { backend = "polling-fallback" }
    END { print backend == "" ? "unknown" : backend }
  ' "$BRIDGE_LOG_ARCHIVE" "$BRIDGE_LOG" 2>/dev/null || true)
  if [[ $backend == unknown || $backend == starting ]]; then
    while IFS= read -r pid; do
      [[ -r /proc/$pid/cmdline ]] || continue
      command_line=$(tr '\0' ' ' <"/proc/$pid/cmdline")
      if [[ $command_line == *"$STATE_DIR"* && $command_line == *close_write,create,delete,moved_to* ]]; then
        printf 'inotify\n'
        return
      fi
    done < <(pgrep -x inotifywait || true)
    printf 'polling-fallback\n'
    return
  fi
  printf '%s\n' "$backend"
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

wait_for_events() {
  local before_bytes=$1
  local lines_file=$2
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local current_bytes

  WAIT_PALETTE_LINE=""
  WAIT_CSS_LINE=""

  while (( SECONDS < deadline )); do
    if [[ -f $BRIDGE_LOG ]]; then
      current_bytes=$(log_size)
      if (( current_bytes != before_bytes )); then
        read_log_since "$before_bytes" "$current_bytes" "$lines_file" || return 2
        WAIT_PALETTE_LINE=$(grep -m1 -F 'PALETTE_APPLIED ' "$lines_file" || true)
        WAIT_CSS_LINE=$(grep -m1 -F 'CHROME_CSS_APPLIED ' "$lines_file" || true)
        if [[ -n $WAIT_PALETTE_LINE && -n $WAIT_CSS_LINE ]]; then
          sleep "$SETTLE_SECONDS"
          current_bytes=$(log_size)
          read_log_since "$before_bytes" "$current_bytes" "$lines_file" || return 2
          WAIT_PALETTE_LINE=$(grep -m1 -F 'PALETTE_APPLIED ' "$lines_file" || true)
          WAIT_CSS_LINE=$(grep -m1 -F 'CHROME_CSS_APPLIED ' "$lines_file" || true)
          return 0
        fi
      fi
    fi
    sleep 0.01
  done

  return 1
}

profile_from_line() {
  local line=$1
  sed -n 's/.* profile=\([^ ]*\).*/\1/p' <<<"$line"
}

record_sample() {
  local mode=$1
  local iteration=$2
  local sync_ms=$3
  local trigger_to_palette_ms=$4
  local trigger_to_css_ms=$5
  local palette_to_css_ms=$6
  local palette_events=$7
  local css_events=$8
  local profile=$9

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$mode" "$iteration" "$sync_ms" "$trigger_to_palette_ms" \
    "$trigger_to_css_ms" "$palette_to_css_ms" "$palette_events" \
    "$css_events" "$profile" >>"$SAMPLES_FILE"
}

run_atomic_sample() {
  local iteration=$1
  local before_bytes
  local temporary
  local trigger_ns
  local lines_file
  local palette_ns
  local css_ns
  local palette_to_css_ms
  local profile
  local palette_events
  local css_events

  before_bytes=$(log_size)
  temporary=$(mktemp "$STATE_DIR/.omazen-benchmark-palette.XXXXXX")
  cp -- "$PALETTE_FILE" "$temporary"
  chmod 600 "$temporary"
  mv -f -- "$temporary" "$PALETTE_FILE"
  trigger_ns=$(now_ns)

  lines_file="$TEMP_DIR/atomic-$iteration.log"
  if wait_for_events "$before_bytes" "$lines_file"; then
    :
  else
    local wait_status=$?
    case $wait_status in
      2) die "bridge.log rotated while waiting; rerun with a quiet bridge log" ;;
      *) die "timed out waiting for bridge events in atomic sample $iteration" ;;
    esac
  fi

  palette_ns=$(line_timestamp "$WAIT_PALETTE_LINE")
  css_ns=$(line_timestamp "$WAIT_CSS_LINE")
  palette_to_css_ms=$(delta_ms "$palette_ns" "$css_ns")
  profile=$(profile_from_line "$WAIT_PALETTE_LINE")
  palette_events=$(grep -c -F 'PALETTE_APPLIED ' "$lines_file" || true)
  css_events=$(grep -c -F 'CHROME_CSS_APPLIED ' "$lines_file" || true)

  record_sample \
    atomic "$iteration" "" \
    "$(delta_ms "$trigger_ns" "$palette_ns")" \
    "$(delta_ms "$trigger_ns" "$css_ns")" \
    "$palette_to_css_ms" "$palette_events" "$css_events" "$profile"
  printf 'atomic sample %d: palette=%sms css=%sms profiles=%s\n' \
    "$iteration" "$(delta_ms "$trigger_ns" "$palette_ns")" \
    "$(delta_ms "$trigger_ns" "$css_ns")" "$palette_events"
}

run_sync_sample() {
  local iteration=$1
  local before_bytes
  local sync_start
  local sync_end
  local sync_ms
  local lines_file
  local palette_ns
  local css_ns
  local palette_to_css_ms
  local profile
  local palette_events
  local css_events
  local sync_output

  before_bytes=$(log_size)
  sync_start=$(now_ns)
  if ! sync_output=$("$OMAZEN_BIN" sync 2>&1); then
    printf '%s\n' "$sync_output" >&2
    die "omazen sync failed in sample $iteration"
  fi
  sync_end=$(now_ns)
  sync_ms=$(delta_ms "$sync_start" "$sync_end")

  lines_file="$TEMP_DIR/sync-$iteration.log"
  if wait_for_events "$before_bytes" "$lines_file"; then
    :
  else
    local wait_status=$?
    case $wait_status in
      2) die "bridge.log rotated while waiting; rerun with a quiet bridge log" ;;
      *) die "timed out waiting for bridge events in sync sample $iteration" ;;
    esac
  fi

  palette_ns=$(line_timestamp "$WAIT_PALETTE_LINE")
  css_ns=$(line_timestamp "$WAIT_CSS_LINE")
  palette_to_css_ms=$(delta_ms "$palette_ns" "$css_ns")
  profile=$(profile_from_line "$WAIT_PALETTE_LINE")
  palette_events=$(grep -c -F 'PALETTE_APPLIED ' "$lines_file" || true)
  css_events=$(grep -c -F 'CHROME_CSS_APPLIED ' "$lines_file" || true)

  record_sample \
    sync "$iteration" "$sync_ms" \
    "$(delta_ms "$sync_start" "$palette_ns")" \
    "$(delta_ms "$sync_start" "$css_ns")" \
    "$palette_to_css_ms" "$palette_events" "$css_events" "$profile"
  printf 'sync sample %d: command=%sms palette=%sms css=%sms profiles=%s\n' \
    "$iteration" "$sync_ms" \
    "$(delta_ms "$sync_start" "$palette_ns")" \
    "$(delta_ms "$sync_start" "$css_ns")" "$palette_events"
}

metric_summary() {
  local mode=$1
  local column=$2
  local label=$3
  local values
  local count
  local min
  local median
  local mean
  local p95
  local p99
  local max

  values=$(awk -F, -v wanted="$mode" -v column="$column" \
    'NR > 1 && $1 == wanted && $column != "" { print $column }' \
    "$SAMPLES_FILE" | sort -n)
  [[ -n $values ]] || return 0
  count=$(wc -l <<<"$values")
  min=$(head -n 1 <<<"$values")
  max=$(tail -n 1 <<<"$values")
  median=$(awk '{ values[NR] = $1 } END { if (NR % 2) print values[(NR + 1) / 2]; else printf "%.3f\n", (values[NR / 2] + values[NR / 2 + 1]) / 2 }' <<<"$values")
  mean=$(awk '{ total += $1 } END { printf "%.3f\n", total / NR }' <<<"$values")
  p95=$(awk -v percentile=0.95 '{ values[NR] = $1 } END { position = 1 + (NR - 1) * percentile; lower = int(position); upper = lower + 1; if (upper > NR) print values[NR]; else printf "%.3f\n", values[lower] + (position - lower) * (values[upper] - values[lower]) }' <<<"$values")
  p99=$(awk -v percentile=0.99 '{ values[NR] = $1 } END { position = 1 + (NR - 1) * percentile; lower = int(position); upper = lower + 1; if (upper > NR) print values[NR]; else printf "%.3f\n", values[lower] + (position - lower) * (values[upper] - values[lower]) }' <<<"$values")
  printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$label" "$count" "$min" "$median" "$mean" "$p95" "$p99" "$max" >>"$REPORT_FILE"
}

write_report() {
  {
    printf '# Omazen benchmark\n\n'
    printf "Date: \`%s\`\n\n" "$(date -Is)"
    printf "This benchmark measures the currently installed bridge. Bridge event precision is limited to milliseconds because \`bridge.log\` records ISO timestamps with millisecond precision.\n\n"
    printf "Watcher backend: \`%s\`\n\n" "$WATCHER_BACKEND"
    printf '## Methodology\n\n'
    printf -- "- \`sync\`: measures from the start of \`bin/omazen sync\` to \`PALETTE_APPLIED\` and \`CHROME_CSS_APPLIED\`; it does not include the complete \`omarchy theme set\` staging process.\n"
    printf -- "- \`atomic\`: replaces \`palette.json\` with an identical copy using \`mv\` and measures from the replacement to both events. It does not change the visible colors.\n"
    printf -- "- \`palette → CSS\`: measures the difference between \`PALETTE_APPLIED\` and \`CHROME_CSS_APPLIED\`.\n"
    printf -- "- Each sample waits for both events before continuing; events from all windows are counted in \`samples.csv\`.\n\n"
    printf -- "- The benchmark waits \`%ss\` after the first CSS event to collect events from other windows.\n\n" "$SETTLE_SECONDS"
    printf '## Results\n'
  } >"$REPORT_FILE"

  for selected_mode in sync atomic; do
    if [[ $MODE == all || $MODE == "$selected_mode" ]]; then
      {
        printf '\n### %s\n\n' "$selected_mode"
        printf '| Metric | N | Minimum (ms) | p50 (ms) | Mean (ms) | p95 (ms) | p99 (ms) | Maximum (ms) |\n'
        printf '|---|---:|---:|---:|---:|---:|---:|---:|\n'
      } >>"$REPORT_FILE"
      if [[ $selected_mode == sync ]]; then
        metric_summary sync 3 'Sync duration'
      fi
      metric_summary "$selected_mode" 4 'Trigger → PALETTE_APPLIED'
      metric_summary "$selected_mode" 5 'Trigger → CHROME_CSS_APPLIED'
      metric_summary "$selected_mode" 6 'PALETTE_APPLIED → CHROME_CSS_APPLIED'
    fi
  done

  {
    printf '\n## Files\n\n'
    printf -- "- Complete data: \`samples.csv\`\n"
    printf -- "- Observed bridge: \`%s\`\n" "$BRIDGE_LOG"
    printf -- "- Observed palette: \`%s\`\n" "$PALETTE_FILE"
  } >>"$REPORT_FILE"
}

while (( $# > 0 )); do
  case $1 in
    --mode)
      (( $# >= 2 )) || die "--mode requires a value"
      MODE=$2
      shift 2
      ;;
    --iterations)
      (( $# >= 2 )) || die "--iterations requires a value"
      ITERATIONS=$2
      shift 2
      ;;
    --timeout)
      (( $# >= 2 )) || die "--timeout requires a value"
      TIMEOUT_SECONDS=$2
      shift 2
      ;;
    --settle)
      (( $# >= 2 )) || die "--settle requires a value"
      SETTLE_SECONDS=$2
      shift 2
      ;;
    --output-dir)
      (( $# >= 2 )) || die "--output-dir requires a value"
      OUTPUT_DIR=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
done

[[ $MODE == sync || $MODE == atomic || $MODE == all ]] || die "mode must be sync, atomic, or all"
[[ $ITERATIONS =~ ^[1-9][0-9]*$ ]] || die "iterations must be a positive integer"
[[ $TIMEOUT_SECONDS =~ ^[1-9][0-9]*$ ]] || die "timeout must be a positive integer"
[[ $SETTLE_SECONDS =~ ^[0-9]+$ ]] || die "settle must be a non-negative integer"
[[ -x $OMAZEN_BIN ]] || die "omazen executable not found: $OMAZEN_BIN"
[[ -f $PALETTE_FILE ]] || die "palette file not found: $PALETTE_FILE"
[[ -f $BRIDGE_LOG ]] || die "bridge log not found: $BRIDGE_LOG; start Zen with Omazen loaded first"

if [[ -z $OUTPUT_DIR ]]; then
  OUTPUT_DIR="/tmp/omazen-benchmark-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p -- "$OUTPUT_DIR"
SAMPLES_FILE="$OUTPUT_DIR/samples.csv"
REPORT_FILE="$OUTPUT_DIR/report.md"
TEMP_DIR=$(mktemp -d /tmp/omazen-benchmark.XXXXXX)
WATCHER_BACKEND=$(watcher_backend)
cleanup() {
  if [[ -n $TEMP_DIR && -d $TEMP_DIR ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

printf 'mode,iteration,sync_command_ms,trigger_to_palette_ms,trigger_to_css_ms,palette_to_css_ms,palette_events,css_events,first_profile\n' >"$SAMPLES_FILE"

printf 'Benchmarking %s mode(s), %d iteration(s) each...\n' "$MODE" "$ITERATIONS"
printf 'Watcher backend: %s\n' "$WATCHER_BACKEND"
if [[ $MODE == sync || $MODE == all ]]; then
  for ((iteration = 1; iteration <= ITERATIONS; iteration += 1)); do
    run_sync_sample "$iteration"
    sleep 0.4
  done
fi
if [[ $MODE == atomic || $MODE == all ]]; then
  for ((iteration = 1; iteration <= ITERATIONS; iteration += 1)); do
    run_atomic_sample "$iteration"
    sleep 0.4
  done
fi

write_report
printf '\nReport: %s\nSamples: %s\n' "$REPORT_FILE" "$SAMPLES_FILE"
