#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
LINTER_DIRECTORY=$(mktemp -d /tmp/omazen-release-linters.XXXXXX)

cleanup() {
  case "$LINTER_DIRECTORY" in
    /tmp/omazen-release-linters.*) rm -rf -- "$LINTER_DIRECTORY" ;;
  esac
}
trap cleanup EXIT

printf '%s\n' '==> Installing pinned static analyzers'
"$PROJECT_ROOT/tests/install-linters.sh" "$LINTER_DIRECTORY"

printf '%s\n' '==> Running static analysis'
PATH="$LINTER_DIRECTORY:$PATH" "$PROJECT_ROOT/tests/lint.sh"

printf '%s\n' '==> Validating Bash, JavaScript, and release consistency'
"$PROJECT_ROOT/tests/syntax.sh"

printf '%s\n' '==> Running disposable lifecycle and regression tests'
"$PROJECT_ROOT/tests/test.sh"

printf '%s\n' '==> Running WCAG palette contrast checks'
node "$PROJECT_ROOT/tests/contrast.mjs"

printf '%s\n' '==> Running rendered-pixel smoke test'
"$PROJECT_ROOT/tests/visual-smoke.sh"

printf '%s\n' '==> Checking repository whitespace'
git -C "$PROJECT_ROOT" diff --check

printf '%s\n' 'Release gate passed.'
