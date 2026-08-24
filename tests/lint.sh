#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

command -v shellcheck >/dev/null 2>&1 || {
  printf 'ERROR: shellcheck is required; run tests/install-linters.sh DIRECTORY and add it to PATH\n' >&2
  exit 1
}
command -v actionlint >/dev/null 2>&1 || {
  printf 'ERROR: actionlint is required; run tests/install-linters.sh DIRECTORY and add it to PATH\n' >&2
  exit 1
}

shellcheck -x --source-path=SCRIPTDIR \
  "$PROJECT_ROOT/bin/omazen" \
  "$PROJECT_ROOT/install.sh" \
  "$PROJECT_ROOT/uninstall.sh" \
  "$PROJECT_ROOT/hooks/theme-set" \
  "$PROJECT_ROOT"/tests/*.sh

actionlint "$PROJECT_ROOT"/.github/workflows/*.yml

printf 'Static analysis passed.\n'
