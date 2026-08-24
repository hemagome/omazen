#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

SHELLCHECK_VERSION=0.11.0
SHELLCHECK_SHA256=b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6
ACTIONLINT_VERSION=1.7.12
ACTIONLINT_SHA256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
DESTINATION=${1:?usage: install-linters.sh DESTINATION}

[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  printf 'ERROR: pinned linter installer supports Linux x86_64 only\n' >&2
  exit 1
}

WORK_DIRECTORY=$(mktemp -d /tmp/omazen-linters.XXXXXX)
cleanup() {
  case "$WORK_DIRECTORY" in
    /tmp/omazen-linters.*) rm -rf -- "$WORK_DIRECTORY" ;;
  esac
}
trap cleanup EXIT

download_and_verify() {
  local url=$1
  local expected=$2
  local output=$3

  curl --fail --location --proto '=https' --retry 3 --silent --show-error \
    --output "$output" "$url"
  printf '%s  %s\n' "$expected" "$output" | sha256sum --check --status
}

shellcheck_archive="$WORK_DIRECTORY/shellcheck.tar.gz"
actionlint_archive="$WORK_DIRECTORY/actionlint.tar.gz"

download_and_verify \
  "https://github.com/koalaman/shellcheck/releases/download/v$SHELLCHECK_VERSION/shellcheck-v$SHELLCHECK_VERSION.linux.x86_64.tar.gz" \
  "$SHELLCHECK_SHA256" "$shellcheck_archive"
download_and_verify \
  "https://github.com/rhysd/actionlint/releases/download/v$ACTIONLINT_VERSION/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
  "$ACTIONLINT_SHA256" "$actionlint_archive"

mkdir -p -- "$DESTINATION"
tar -xzf "$shellcheck_archive" -C "$WORK_DIRECTORY"
tar -xzf "$actionlint_archive" -C "$WORK_DIRECTORY"
install -m 0755 \
  "$WORK_DIRECTORY/shellcheck-v$SHELLCHECK_VERSION/shellcheck" \
  "$DESTINATION/shellcheck"
install -m 0755 "$WORK_DIRECTORY/actionlint" "$DESTINATION/actionlint"

printf 'Installed ShellCheck %s and actionlint %s in %s\n' \
  "$SHELLCHECK_VERSION" "$ACTIONLINT_VERSION" "$DESTINATION"
