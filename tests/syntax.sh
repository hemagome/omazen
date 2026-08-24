#!/bin/bash

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

shell_files=(
  "$PROJECT_ROOT/bin/omazen"
  "$PROJECT_ROOT/install.sh"
  "$PROJECT_ROOT/uninstall.sh"
  "$PROJECT_ROOT/hooks/theme-set"
  "$PROJECT_ROOT"/lib/*.sh
  "$PROJECT_ROOT"/tests/*.sh
)
for shell_file in "${shell_files[@]}"; do
  bash -n "$shell_file"
done

javascript_files=(
  "$PROJECT_ROOT/zen/omazen-bridge.uc.js"
  "$PROJECT_ROOT/zen/Omazen/OmazenChild.sys.mjs"
  "$PROJECT_ROOT/zen/Omazen/OmazenParent.sys.mjs"
)
for javascript_file in "${javascript_files[@]}"; do
  node --check "$javascript_file"
done

printf 'Syntax checks passed.\n'
