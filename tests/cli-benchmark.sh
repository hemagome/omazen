#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
OMAZEN_BIN=${OMAZEN_BIN:-"$PROJECT_ROOT/bin/omazen"}
OUTPUT_DIR=""
RUNS=3
ITERATIONS=100
WARMUPS=10

usage() {
  cat <<'EOF'
Usage: tests/cli-benchmark.sh --output-dir DIR [options]

Options:
  --runs N          Independent runs (default: 3)
  --iterations N    Measured sync samples per run (default: 100)
  --warmups N       Warm-up samples per run (default: 10)
  --binary PATH     CLI implementation to measure
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

while (( $# > 0 )); do
  case $1 in
    --output-dir) OUTPUT_DIR=${2:-}; shift 2 ;;
    --runs) RUNS=${2:-}; shift 2 ;;
    --iterations) ITERATIONS=${2:-}; shift 2 ;;
    --warmups) WARMUPS=${2:-}; shift 2 ;;
    --binary) OMAZEN_BIN=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

[[ -n $OUTPUT_DIR ]] || die "--output-dir is required"
[[ -x $OMAZEN_BIN ]] || die "binary is not executable: $OMAZEN_BIN"
for value in "$RUNS" "$ITERATIONS"; do
  [[ $value =~ ^[1-9][0-9]*$ ]] || die "runs and iterations must be positive integers"
done
[[ $WARMUPS =~ ^[0-9]+$ ]] || die "warmups must be a non-negative integer"
command -v node >/dev/null || die "node is required"
command -v jq >/dev/null || die "jq is required"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd -- "$OUTPUT_DIR" && pwd -P)
TEMP_ROOT=$(mktemp -d /tmp/omazen-cli-benchmark.XXXXXX)
cleanup() {
  case "$TEMP_ROOT" in
    /tmp/omazen-cli-benchmark.*) rm -rf -- "$TEMP_ROOT" ;;
  esac
}
trap cleanup EXIT

COLORS="$TEMP_ROOT/colors.toml"
cat >"$COLORS" <<'EOF'
mode = "dark"
accent = "#89b4fa"
selection = "#45475a"
muted = "#6c7086"
background = "#1e1e2e"
dark_background = "#181825"
lighter_background = "#313244"
foreground = "#cdd6f4"
EOF

LATENCY="$OUTPUT_DIR/latency.csv"
CPU="$OUTPUT_DIR/cpu.csv"
MEMORY="$OUTPUT_DIR/memory.csv"
printf 'implementation,scenario,run,iteration,outcome,wall_ns,warnings\n' >"$LATENCY"
printf 'implementation,scenario,run,iteration,user_cpu_ns,system_cpu_ns,observed_processes,max_concurrent_processes\n' >"$CPU"
printf 'implementation,scenario,run,iteration,max_process_tree_rss_bytes,max_process_tree_pss_bytes,samples\n' >"$MEMORY"

implementation=${OMAZEN_IMPLEMENTATION:-bash}
git_commit=$(git -C "$PROJECT_ROOT" rev-parse HEAD)
kernel=$(uname -srmo)
cpu_model=$(awk -F: '/^model name/ { sub(/^[[:space:]]+/, "", $2); print $2; exit }' /proc/cpuinfo)
logical_cpus=$(getconf _NPROCESSORS_ONLN)
memory_bytes=$(awk '/^MemTotal:/ { print $2 * 1024; exit }' /proc/meminfo)
filesystem=$(findmnt -T "$PROJECT_ROOT" -n -o FSTYPE)
governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || printf 'unknown')
load_average=$(awk '{ print $1 " " $2 " " $3 }' /proc/loadavg)
node_version=$(node --version)
jq_version=$(jq --version)
binary_sha256=$(sha256sum "$OMAZEN_BIN" | awk '{ print $1 }')
jq -n \
  --arg implementation "$implementation" \
  --arg git_commit "$git_commit" \
  --arg omazen_version "$(<"$PROJECT_ROOT/VERSION")" \
  --arg kernel "$kernel" \
  --arg cpu_model "$cpu_model" \
  --argjson logical_cpus "$logical_cpus" \
  --argjson memory_bytes "$memory_bytes" \
  --arg filesystem "$filesystem" \
  --arg governor "$governor" \
  --arg load_average "$load_average" \
  --arg node_version "$node_version" \
  --arg jq_version "$jq_version" \
  --arg binary_sha256 "$binary_sha256" \
  --argjson runs "$RUNS" \
  --argjson iterations "$ITERATIONS" \
  --argjson warmups "$WARMUPS" \
  '{
    schema_version: 1,
    implementation: $implementation,
    git_commit: $git_commit,
    omazen_version: $omazen_version,
    rustc: null,
    cargo: null,
    kernel: $kernel,
    cpu_model: $cpu_model,
    logical_cpus: $logical_cpus,
    memory_bytes: $memory_bytes,
    filesystem: $filesystem,
    cpu_governor: $governor,
    load_average_at_start: $load_average,
    node: $node_version,
    jq: $jq_version,
    binary_sha256: $binary_sha256,
    scenario: "cli-sync-disposable",
    watcher_backend: "not-applicable",
    zen_windows: 0,
    runs: $runs,
    measured_iterations_per_run: $iterations,
    warmups_per_run: $warmups,
    timeout_seconds: null,
    warnings: [
      "CPU ticks have the kernel CLK_TCK resolution.",
      "Transient descendants can exit between /proc samples and remain visible through sampler warnings."
    ]
  }' >"$OUTPUT_DIR/environment.json"

for ((run = 1; run <= RUNS; run += 1)); do
  STATE="$TEMP_ROOT/run-$run/state"
  mkdir -p "$STATE"
  export OMAZEN_HOME_DIR="$TEMP_ROOT/run-$run/home"
  export OMAZEN_STATE_DIR="$STATE"
  export OMAZEN_ACTIVE_COLORS="$COLORS"
  export OMAZEN_SKIP_THEME_HOOK=1
  for ((warmup = 1; warmup <= WARMUPS; warmup += 1)); do
    "$OMAZEN_BIN" sync >/dev/null
  done
  for ((iteration = 1; iteration <= ITERATIONS; iteration += 1)); do
    metrics_file="$TEMP_ROOT/metrics.json"
    status=0
    node "$PROJECT_ROOT/tests/process-tree-metrics.mjs" -- "$OMAZEN_BIN" sync \
      >"$metrics_file" || status=$?
    outcome=ok
    (( status == 0 )) || outcome="exit-$status"
    warning=$(jq -r '.warnings | join(";")' "$metrics_file")
    printf '%s,%s,%d,%d,%s,%s,%s\n' \
      "$implementation" cli-sync "$run" "$iteration" "$outcome" \
      "$(jq -r .wall_ns "$metrics_file")" "$warning" >>"$LATENCY"
    printf '%s,%s,%d,%d,%s,%s,%s,%s\n' \
      "$implementation" cli-sync "$run" "$iteration" \
      "$(jq -r .user_cpu_ns "$metrics_file")" \
      "$(jq -r .system_cpu_ns "$metrics_file")" \
      "$(jq -r .observed_processes "$metrics_file")" \
      "$(jq -r .max_concurrent_processes "$metrics_file")" >>"$CPU"
    printf '%s,%s,%d,%d,%s,%s,%s\n' \
      "$implementation" cli-sync "$run" "$iteration" \
      "$(jq -r .max_process_tree_rss_bytes "$metrics_file")" \
      "$(jq -r .max_process_tree_pss_bytes "$metrics_file")" \
      "$(jq -r .samples "$metrics_file")" >>"$MEMORY"
  done
done

node "$PROJECT_ROOT/tests/generate-benchmark-report.mjs" "$OUTPUT_DIR"
printf 'Benchmark data: %s\n' "$OUTPUT_DIR"
