#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
VERSION=$(<"$PROJECT_ROOT/VERSION")
BRIDGE="$PROJECT_ROOT/zen/omazen-bridge.uc.js"
CHILD="$PROJECT_ROOT/zen/Omazen/OmazenChild.sys.mjs"
CI_WORKFLOW="$PROJECT_ROOT/.github/workflows/ci.yml"
CHROME_CSS="omazen-chrome-v${VERSION}.css"
CONTENT_CSS="omazen-content-v${VERSION}.css"
FX_AUTOCONFIG="$PROJECT_ROOT/vendor/fx-autoconfig"
FX_AUTOCONFIG_VERSION=0.10.16
FX_AUTOCONFIG_COMMIT=dfdab5684faffc112b76ccb1d8cab7f75da0102c

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
# The real compositor-backed visual test must follow VERSION when the release
# CSS filenames change, rather than silently testing a stale stylesheet.
grep -Fq -- "omazen-chrome-v\${RELEASE_VERSION}.css" \
  "$PROJECT_ROOT/tests/visual-integration.sh" || fail "visual integration chrome stylesheet version"
grep -Fq -- "omazen-content-v\${RELEASE_VERSION}.css" \
  "$PROJECT_ROOT/tests/visual-integration.sh" || fail "visual integration content stylesheet version"
[[ -f $PROJECT_ROOT/tests/contrast.mjs ]] || fail "contrast validation test is missing"
[[ -d $PROJECT_ROOT/tests/fixtures/contrast-palettes ]] || fail "contrast fallback fixtures are missing"
grep -Eq -- '^[[:space:]]+ZEN_VERSION:[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+[[:alnum:]_.-]*[[:space:]]*$' \
  "$CI_WORKFLOW" || fail "CI Zen version pin is missing or malformed"
grep -Eq -- '^[[:space:]]+ZEN_SHA256:[[:space:]]+[0-9a-f]{64}[[:space:]]*$' \
  "$CI_WORKFLOW" || fail "CI Zen SHA-256 pin is missing or malformed"
zen_hash_line=$(grep -nF -- 'sha256sum --check --status' "$CI_WORKFLOW" | cut -d: -f1) || \
  fail "CI Zen archive hash verification is missing"
zen_extract_line=$(grep -nF -- 'tar --strip-components=1 -xf' "$CI_WORKFLOW" | cut -d: -f1) || \
  fail "CI Zen archive extraction is missing"
(( zen_hash_line < zen_extract_line )) || fail "CI verifies Zen after extraction"
# shellcheck disable=SC2016 # Match the literal shell source, not expanded values.
grep -Fq -- 'OMAZEN_VERSION=$(<"$OMAZEN_ROOT/VERSION")' "$PROJECT_ROOT/lib/common.sh" || \
  fail "shell runtime does not read VERSION"
# shellcheck disable=SC2016 # Match the literal shell source, not expanded values.
grep -Fq -- 'printf '\''%s\n'\'' "$OMAZEN_VERSION" >"$STAGING/.omazen-installed"' \
  "$PROJECT_ROOT/install.sh" || fail "installer marker does not use VERSION"
if grep -Rqs -- 'STATE_LEAF' "$PROJECT_ROOT/zen"; then
  fail "dead STATE_LEAF declaration remains"
fi

(
  cd -- "$FX_AUTOCONFIG"
  sha256sum --check --strict SHA256SUMS >/dev/null
  expected_files=$(awk '{print $2}' SHA256SUMS | LC_ALL=C sort)
  actual_files=$(find program profile -type f -print | LC_ALL=C sort)
  [[ $actual_files == "$expected_files" ]]
) || fail "vendored fx-autoconfig files do not match the pinned manifest"
grep -Fq -- "$FX_AUTOCONFIG_COMMIT" "$FX_AUTOCONFIG/UPSTREAM.md" || \
  fail "fx-autoconfig commit provenance is inconsistent"
grep -Fq -- "Loader version: \`$FX_AUTOCONFIG_VERSION\`" "$FX_AUTOCONFIG/UPSTREAM.md" || \
  fail "fx-autoconfig version provenance is inconsistent"
while read -r checksum path; do
  grep -Fq -- "$checksum" "$FX_AUTOCONFIG/UPSTREAM.md" || \
    fail "fx-autoconfig documented checksum is inconsistent: $path"
done <"$FX_AUTOCONFIG/SHA256SUMS"

printf 'Release consistency checks passed for %s.\n' "$VERSION"
