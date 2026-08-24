#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
VERSION=$(<"$PROJECT_ROOT/VERSION")
BRIDGE="$PROJECT_ROOT/zen/omazen-bridge.uc.js"
CHILD="$PROJECT_ROOT/zen/Omazen/OmazenChild.sys.mjs"
CHROME_CSS="omazen-chrome-v${VERSION}.css"
CONTENT_CSS="omazen-content-v${VERSION}.css"

fail() {
  printf 'Release consistency error: %s\n' "$*" >&2
  exit 1
}

[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION is not semantic x.y.z"
grep -Fqx -- "// @version        $VERSION" "$BRIDGE" || fail "bridge metadata version"
grep -Fqx -- "  const VERSION = \"$VERSION\";" "$BRIDGE" || fail "bridge runtime version"
grep -Fq -- "/$CHROME_CSS\";" "$BRIDGE" || fail "bridge chrome stylesheet URI"
grep -Fq -- "/$CONTENT_CSS\";" "$BRIDGE" || fail "bridge content stylesheet URI"
grep -Fq -- "/$CONTENT_CSS\";" "$CHILD" || fail "child actor stylesheet URI"
grep -Fq -- 'Omazen/OmazenPalette.sys.mjs' "$BRIDGE" || fail "bridge shared palette module"
grep -Fq -- 'from "./OmazenPalette.sys.mjs";' "$CHILD" || fail "child shared palette module"
[[ -f $PROJECT_ROOT/zen/Omazen/$CHROME_CSS ]] || fail "missing versioned chrome stylesheet"
[[ -f $PROJECT_ROOT/zen/Omazen/$CONTENT_CSS ]] || fail "missing versioned content stylesheet"
grep -Fq -- "omazen-content-v$VERSION.css" \
  "$PROJECT_ROOT/tests/fixtures/visual-smoke.html" || fail "visual fixture stylesheet version"
grep -Fq -- 'OMAZEN_VERSION=$(<"$OMAZEN_ROOT/VERSION")' "$PROJECT_ROOT/lib/common.sh" || \
  fail "shell runtime does not read VERSION"
grep -Fq -- 'printf '\''%s\n'\'' "$OMAZEN_VERSION" >"$STAGING/.omazen-installed"' \
  "$PROJECT_ROOT/install.sh" || fail "installer marker does not use VERSION"
if grep -Rqs -- 'STATE_LEAF' "$PROJECT_ROOT/zen"; then
  fail "dead STATE_LEAF declaration remains"
fi

printf 'Release consistency checks passed for %s.\n' "$VERSION"
