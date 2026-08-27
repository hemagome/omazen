#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

shell_files=(
  "$PROJECT_ROOT/bin/omazen"
  "$PROJECT_ROOT/install.sh"
  "$PROJECT_ROOT/uninstall.sh"
  "$PROJECT_ROOT/hooks/theme-set"
  "$PROJECT_ROOT"/tests/*.sh
)
for shell_file in "${shell_files[@]}"; do
  bash -n "$shell_file"
done

javascript_files=(
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js"
  "$PROJECT_ROOT/zen/Omazen/OmazenChild.sys.mjs"
  "$PROJECT_ROOT/zen/Omazen/OmazenPalette.sys.mjs"
  "$PROJECT_ROOT/zen/Omazen/OmazenParent.sys.mjs"
  "$PROJECT_ROOT/zen/Omazen/OmazenWatcher.sys.mjs"
  "$PROJECT_ROOT/tests/bridge-regressions.mjs"
  "$PROJECT_ROOT/tests/contrast.mjs"
  "$PROJECT_ROOT/tests/js-regressions.mjs"
  "$PROJECT_ROOT/tests/generate-benchmark-report.mjs"
  "$PROJECT_ROOT/tests/process-tree-metrics.mjs"
  "$PROJECT_ROOT/tests/watcher-regressions.mjs"
)
for javascript_file in "${javascript_files[@]}"; do
  node --check "$javascript_file"
done

"$PROJECT_ROOT/tests/release-consistency.sh"

printf 'Syntax checks passed.\n'
