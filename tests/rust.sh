#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

command -v rustc >/dev/null 2>&1 || {
  printf 'ERROR: rustc 1.98.0 is required\n' >&2
  exit 1
}
command -v cargo >/dev/null 2>&1 || {
  printf 'ERROR: Cargo 1.98.0 is required\n' >&2
  exit 1
}

rustc -vV
[[ $(rustc --version) == 'rustc 1.98.0 '* ]] || {
  printf 'ERROR: expected rustc 1.98.0\n' >&2
  exit 1
}

cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked
cargo build --release --locked

OMAZEN_REFERENCE_BIN="$PROJECT_ROOT/bin/omazen" \
OMAZEN_CANDIDATE_BIN="$PROJECT_ROOT/target/release/omazen-rust" \
  "$PROJECT_ROOT/tests/sync-contract.sh"
OMAZEN_REFERENCE_BIN="$PROJECT_ROOT/bin/omazen" \
OMAZEN_CANDIDATE_BIN="$PROJECT_ROOT/target/release/omazen-rust" \
  "$PROJECT_ROOT/tests/read-only-contract.sh"
OMAZEN_REFERENCE_BIN="$PROJECT_ROOT/bin/omazen" \
OMAZEN_CANDIDATE_BIN="$PROJECT_ROOT/target/release/omazen-rust" \
  "$PROJECT_ROOT/tests/state-contract.sh"
OMAZEN_RUST_BIN="$PROJECT_ROOT/target/release/omazen-rust" \
  "$PROJECT_ROOT/tests/test.sh"

printf 'Rust checks passed.\n'
