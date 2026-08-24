#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
VERSION=$(<"$PROJECT_ROOT/VERSION")
TAG="v$VERSION"

fail() {
  printf 'Release tag error: %s\n' "$*" >&2
  exit 1
}

validate_version() {
  [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
    fail "VERSION is not semantic x.y.z: $VERSION"
  git -C "$PROJECT_ROOT" check-ref-format "refs/tags/$TAG" || \
    fail "derived tag is not a valid Git ref: $TAG"
  grep -Eq -- "^## \\[$VERSION\\]( |$)" "$PROJECT_ROOT/CHANGELOG.md" || \
    fail "CHANGELOG.md has no release section for $VERSION"
  "$PROJECT_ROOT/tests/release-consistency.sh" >/dev/null || \
    fail "release consistency checks failed"
}

check_tag() {
  local candidate=${1:-}
  [[ $candidate == "$TAG" ]] || \
    fail "tag $candidate does not match VERSION $VERSION (expected $TAG)"
  git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/tags/$candidate" || \
    fail "tag does not exist: $candidate"
  [[ $(git -C "$PROJECT_ROOT" rev-list -n 1 "$candidate") == \
    "$(git -C "$PROJECT_ROOT" rev-parse HEAD)" ]] || \
    fail "tag $candidate does not point to HEAD"
}

validate_version

case ${1:-} in
  "")
    [[ -z $(git -C "$PROJECT_ROOT" status --porcelain) ]] || \
      fail "worktree is not clean; commit release changes before tagging"
    if git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/tags/$TAG"; then
      check_tag "$TAG"
      printf '%s\n' "$TAG"
      exit 0
    fi
    git -C "$PROJECT_ROOT" tag -a "$TAG" -m "Omazen $VERSION"
    printf '%s\n' "$TAG"
    ;;
  --check)
    [[ $# -eq 2 ]] || fail "usage: $0 [--check TAG]"
    check_tag "$2"
    ;;
  *)
    fail "usage: $0 [--check TAG]"
    ;;
esac
