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

missing_binary_stderr=$(mktemp /tmp/omazen-missing-rust.XXXXXX)
cleanup_missing_binary_test() {
  rm -f -- "$missing_binary_stderr"
}
trap cleanup_missing_binary_test EXIT
if OMAZEN_RUST_BIN="$PROJECT_ROOT/target/release/omazen-rust-does-not-exist" \
  "$PROJECT_ROOT/bin/omazen" help >/dev/null 2>"$missing_binary_stderr"; then
  printf 'ERROR: launcher accepted a missing Rust CLI\n' >&2
  exit 1
fi
grep -Fq -- 'ERROR: Omazen Rust CLI is missing or not executable:' \
  "$missing_binary_stderr" || {
    printf 'ERROR: launcher did not diagnose a missing Rust CLI\n' >&2
    exit 1
  }
printf 'ok - launcher fails closed when the Rust CLI is missing\n'

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
