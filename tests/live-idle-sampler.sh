#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
BENCH_HOME_DIR=${OMAZEN_HOME_DIR:-$HOME}
STATE_DIR=${OMAZEN_STATE_DIR:-"${XDG_STATE_HOME:-$BENCH_HOME_DIR/.local/state}/omazen"}
BRIDGE_LOG="$STATE_DIR/bridge.log"
BRIDGE_LOG_ARCHIVE="$STATE_DIR/bridge.log.1"
DURATION_SECONDS=600
INTERVAL_SECONDS=5
EXPECTED_WINDOWS=""
SCENARIO=""
OUTPUT_DIR=""

usage() {
  cat <<'EOF'
Usage: tests/live-idle-sampler.sh --scenario NAME --windows N --output-dir DIR [options]

Options:
  --duration SEC    Idle interval in seconds (default: 600)
  --interval SEC    Sampling interval in seconds (default: 5)
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

while (( $# > 0 )); do
  case $1 in
    --scenario) SCENARIO=${2:-}; shift 2 ;;
    --windows) EXPECTED_WINDOWS=${2:-}; shift 2 ;;
    --output-dir) OUTPUT_DIR=${2:-}; shift 2 ;;
    --duration) DURATION_SECONDS=${2:-}; shift 2 ;;
    --interval) INTERVAL_SECONDS=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

[[ -n $SCENARIO ]] || die "--scenario is required"
[[ $EXPECTED_WINDOWS =~ ^[1-9][0-9]*$ ]] || die "--windows must be a positive integer"
[[ -n $OUTPUT_DIR ]] || die "--output-dir is required"
[[ $DURATION_SECONDS =~ ^[1-9][0-9]*$ ]] || die "--duration must be a positive integer"
[[ $INTERVAL_SECONDS =~ ^[1-9][0-9]*$ ]] || die "--interval must be a positive integer"
(( DURATION_SECONDS >= INTERVAL_SECONDS )) || die "duration must be at least one interval"
command -v hyprctl >/dev/null || die "hyprctl is required"
command -v jq >/dev/null || die "jq is required"
[[ -f $BRIDGE_LOG ]] || die "bridge log is missing: $BRIDGE_LOG"

mkdir -p -- "$OUTPUT_DIR"
OUTPUT_DIR=$(cd -- "$OUTPUT_DIR" && pwd -P)
SAMPLES_FILE="$OUTPUT_DIR/samples.csv"
ENVIRONMENT_FILE="$OUTPUT_DIR/environment.json"

zen_windows() {
  hyprctl clients -j 2>/dev/null | jq '[.[] | select((.class | ascii_downcase) == "zen")] | length'
}

watcher_backend() {
  local backend
  local -a current_watcher_pids=()
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
    mapfile -t current_watcher_pids < <(watcher_pids)
    if (( ${#current_watcher_pids[@]} > 0 )); then
      printf 'inotify\n'
    else
      printf 'polling-fallback\n'
    fi
    return
  fi
  printf '%s\n' "$backend"
}

zen_pids() {
  pgrep -f '^/opt/zen-browser-bin/zen-bin( |$)' || true
}

watcher_pids() {
  local pid command_line
  while IFS= read -r pid; do
    [[ -r /proc/$pid/cmdline ]] || continue
    command_line=$(tr '\0' ' ' <"/proc/$pid/cmdline")
    [[ $command_line == *"$STATE_DIR"* ]] || continue
    [[ $command_line == *close_write,create,delete,moved_to* ]] || continue
    printf '%s\n' "$pid"
  done < <(pgrep -x inotifywait || true)
}

process_totals() {
  local pid status_line stat_fields stat_rest
  local rss_kib=0 pss_kib=0 pss_processes=0 cpu_ticks=0
  local voluntary=0 involuntary=0 processes=0
  local key value _unit
  local -a stat_parts=()

  for pid in "$@"; do
    [[ -r /proc/$pid/stat && -r /proc/$pid/status ]] || continue
    ((processes += 1))
    stat_fields=$(<"/proc/$pid/stat")
    stat_rest=${stat_fields#*) }
    read -r -a stat_parts <<<"$stat_rest"
    if (( ${#stat_parts[@]} >= 13 )); then
      cpu_ticks=$((cpu_ticks + stat_parts[11] + stat_parts[12]))
    fi
    while read -r key value _unit; do
      case $key in
        VmRSS:) rss_kib=$((rss_kib + value)) ;;
        voluntary_ctxt_switches:) voluntary=$((voluntary + value)) ;;
        nonvoluntary_ctxt_switches:) involuntary=$((involuntary + value)) ;;
      esac
    done <"/proc/$pid/status"
    if [[ -r /proc/$pid/smaps_rollup ]]; then
      while read -r key value _unit; do
        if [[ $key == Pss: ]]; then
          pss_kib=$((pss_kib + value))
          ((pss_processes += 1))
          break
        fi
      done <"/proc/$pid/smaps_rollup"
    fi
  done

  TOTAL_PROCESSES=$processes
  TOTAL_RSS_BYTES=$((rss_kib * 1024))
  TOTAL_PSS_BYTES=$((pss_kib * 1024))
  TOTAL_PSS_PROCESSES=$pss_processes
  TOTAL_CPU_TICKS=$cpu_ticks
  TOTAL_VOLUNTARY=$voluntary
  TOTAL_INVOLUNTARY=$involuntary
}

initial_windows=$(zen_windows)
[[ $initial_windows == "$EXPECTED_WINDOWS" ]] || \
  die "expected $EXPECTED_WINDOWS Zen windows, found $initial_windows"
initial_backend=$(watcher_backend)
clock_ticks=$(getconf CLK_TCK)
sample_count=$((DURATION_SECONDS / INTERVAL_SECONDS + 1))

jq -n \
  --arg scenario "$SCENARIO" \
  --arg start_time "$(date -Is)" \
  --arg git_commit "$(git -C "$PROJECT_ROOT" rev-parse HEAD)" \
  --arg omazen_version "$(<"$PROJECT_ROOT/VERSION")" \
  --arg theme "$(omarchy theme current)" \
  --arg backend "$initial_backend" \
  --arg kernel "$(uname -srmo)" \
  --arg hyprland "$(hyprctl version | head -n 1)" \
  --arg zen_version "$(sed -n 's/^Version=//p' /opt/zen-browser-bin/application.ini | head -n 1)" \
  --argjson expected_windows "$EXPECTED_WINDOWS" \
  --argjson duration_seconds "$DURATION_SECONDS" \
  --argjson interval_seconds "$INTERVAL_SECONDS" \
  --argjson clock_ticks "$clock_ticks" \
  '{
    schema_version: 1,
    scenario: $scenario,
    start_time: $start_time,
    git_commit: $git_commit,
    omazen_version: $omazen_version,
    theme: $theme,
    watcher_backend_at_start: $backend,
    expected_windows: $expected_windows,
    duration_seconds: $duration_seconds,
    interval_seconds: $interval_seconds,
    clock_ticks_per_second: $clock_ticks,
    kernel: $kernel,
    hyprland: $hyprland,
    zen_version: $zen_version
  }' >"$ENVIRONMENT_FILE"

printf '%s\n' 'sample,elapsed_seconds,timestamp,windows,backend,zen_processes,zen_rss_bytes,zen_pss_bytes,zen_pss_processes,zen_cpu_ticks,zen_voluntary_context_switches,zen_involuntary_context_switches,watcher_processes,watcher_rss_bytes,watcher_pss_bytes,watcher_pss_processes,watcher_cpu_ticks,watcher_voluntary_context_switches,watcher_involuntary_context_switches' >"$SAMPLES_FILE"

start_epoch=$(date +%s)
for ((sample = 0; sample < sample_count; sample += 1)); do
  target_epoch=$((start_epoch + sample * INTERVAL_SECONDS))
  now_epoch=$(date +%s)
  if (( now_epoch < target_epoch )); then
    sleep "$((target_epoch - now_epoch))"
  fi
  elapsed=$(( $(date +%s) - start_epoch ))
  windows=$(zen_windows)
  backend=$(watcher_backend)
  mapfile -t current_zen_pids < <(zen_pids)
  process_totals "${current_zen_pids[@]}"
  zen_metrics=("$TOTAL_PROCESSES" "$TOTAL_RSS_BYTES" "$TOTAL_PSS_BYTES" "$TOTAL_PSS_PROCESSES" "$TOTAL_CPU_TICKS" "$TOTAL_VOLUNTARY" "$TOTAL_INVOLUNTARY")
  mapfile -t current_watcher_pids < <(watcher_pids)
  process_totals "${current_watcher_pids[@]}"
  printf '%d,%d,%s,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$sample" "$elapsed" "$(date -Is)" "$windows" "$backend" \
    "${zen_metrics[@]}" "$TOTAL_PROCESSES" "$TOTAL_RSS_BYTES" \
    "$TOTAL_PSS_BYTES" "$TOTAL_PSS_PROCESSES" "$TOTAL_CPU_TICKS" \
    "$TOTAL_VOLUNTARY" "$TOTAL_INVOLUNTARY" >>"$SAMPLES_FILE"
done

final_windows=$(zen_windows)
[[ $final_windows == "$EXPECTED_WINDOWS" ]] || \
  die "window count changed during idle sample: expected $EXPECTED_WINDOWS, found $final_windows"
printf 'Idle samples: %s\nEnvironment: %s\n' "$SAMPLES_FILE" "$ENVIRONMENT_FILE"
