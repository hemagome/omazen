#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

SOURCE_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
OMAZEN_HOME_DIR=${OMAZEN_HOME_DIR:-$HOME}
DESTINATION=${OMAZEN_DATA_DIR:-"${XDG_DATA_HOME:-$OMAZEN_HOME_DIR/.local/share}/omazen"}
BIN_DIRECTORY=${OMAZEN_LOCAL_BIN_DIR:-"${XDG_BIN_HOME:-$OMAZEN_HOME_DIR/.local/bin}"}
OMAZEN_VERSION=$(<"$SOURCE_ROOT/VERSION")
BACKUP="${DESTINATION}.backup.$(date -u +%Y%m%dT%H%M%SZ).${BASHPID}"
STAGING=""
RUST_BINARY=${OMAZEN_RUST_BINARY:-}

cleanup_staging() {
  if [[ -n $STAGING && -d $STAGING ]]; then
    case "$STAGING" in
      "$DESTINATION".staging.*) rm -rf -- "$STAGING" ;;
    esac
  fi
}
trap cleanup_staging EXIT

[[ $OMAZEN_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'ERROR: invalid Omazen VERSION file\n' >&2
  exit 1
}
"$SOURCE_ROOT/tests/release-consistency.sh" >/dev/null

if [[ -z $RUST_BINARY ]]; then
  if [[ -x $SOURCE_ROOT/libexec/omazen-rust ]]; then
    RUST_BINARY="$SOURCE_ROOT/libexec/omazen-rust"
  elif command -v cargo >/dev/null 2>&1; then
    [[ $(rustc --version) == 'rustc 1.98.0 '* ]] || {
      printf 'ERROR: building Omazen requires rustc 1.98.0\n' >&2
      exit 1
    }
    cargo build --manifest-path "$SOURCE_ROOT/Cargo.toml" --release --locked
    RUST_BINARY="$SOURCE_ROOT/target/release/omazen-rust"
  elif [[ -x $SOURCE_ROOT/target/release/omazen-rust ]]; then
    RUST_BINARY="$SOURCE_ROOT/target/release/omazen-rust"
  else
    printf 'ERROR: prebuilt omazen-rust or the pinned Rust 1.98.0 toolchain is required\n' >&2
    exit 1
  fi
fi
[[ -x $RUST_BINARY ]] || {
  printf 'ERROR: Rust CLI binary is not executable: %s\n' "$RUST_BINARY" >&2
  exit 1
}

if [[ -e $DESTINATION && ! -f $DESTINATION/.omazen-installed ]]; then
  printf 'ERROR: refusing to overwrite unowned directory: %s\n' "$DESTINATION" >&2
  exit 1
fi

if [[ -e $BIN_DIRECTORY/omazen && ! -L $BIN_DIRECTORY/omazen ]]; then
  printf 'ERROR: refusing to replace non-symlink command: %s/omazen\n' "$BIN_DIRECTORY" >&2
  exit 1
fi
if [[ -L $BIN_DIRECTORY/omazen ]]; then
  current_target=$(readlink -f -- "$BIN_DIRECTORY/omazen")
  [[ $current_target == "$DESTINATION/bin/omazen" ]] || {
    printf 'ERROR: refusing to replace symlink owned by another installation: %s/omazen\n' "$BIN_DIRECTORY" >&2
    exit 1
  }
fi

mkdir -p -- "$(dirname -- "$DESTINATION")" "$BIN_DIRECTORY"
STAGING=$(mktemp -d "${DESTINATION}.staging.XXXXXX")
for item in bin lib zen hooks vendor docs tests README.md CHANGELOG.md LICENSE NOTICE THIRD_PARTY_LICENSES.md VERSION install.sh uninstall.sh; do
  [[ -e $SOURCE_ROOT/$item ]] || continue
  cp -a -- "$SOURCE_ROOT/$item" "$STAGING/"
done
mkdir -p "$STAGING/libexec"
install -m 0755 -- "$RUST_BINARY" "$STAGING/libexec/omazen-rust"
printf '%s\n' "$OMAZEN_VERSION" >"$STAGING/.omazen-installed"
chmod +x "$STAGING/bin/omazen" "$STAGING/hooks/theme-set" "$STAGING/install.sh" "$STAGING/uninstall.sh"

if [[ ${OMAZEN_INSTALL_NO_SETUP:-0} != 1 ]]; then
  "$STAGING/bin/omazen" setup
fi

if [[ -d $DESTINATION ]]; then
  mv -- "$DESTINATION" "$BACKUP"
  if ! mv -- "$STAGING" "$DESTINATION"; then
    mv -- "$BACKUP" "$DESTINATION"
    printf 'ERROR: failed to activate staged Omazen application; previous copy restored\n' >&2
    exit 1
  fi
  printf 'Backed up previous Omazen application copy: %s\n' "$BACKUP"
else
  mv -- "$STAGING" "$DESTINATION"
fi
STAGING=""

ln -sfn -- "$DESTINATION/bin/omazen" "$BIN_DIRECTORY/omazen"
printf 'Installed Omazen command: %s/omazen\n' "$BIN_DIRECTORY"
