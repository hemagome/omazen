#!/bin/bash

set -euo pipefail

SOURCE_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
OMAZEN_HOME_DIR=${OMAZEN_HOME_DIR:-$HOME}
DESTINATION=${OMAZEN_DATA_DIR:-"${XDG_DATA_HOME:-$OMAZEN_HOME_DIR/.local/share}/omazen"}
BIN_DIRECTORY=${OMAZEN_LOCAL_BIN_DIR:-"${XDG_BIN_HOME:-$OMAZEN_HOME_DIR/.local/bin}"}
BACKUP="${DESTINATION}.backup.$(date -u +%Y%m%dT%H%M%SZ)"

if [[ -e $DESTINATION && ! -f $DESTINATION/.omazen-installed ]]; then
  printf 'ERROR: refusing to overwrite unowned directory: %s\n' "$DESTINATION" >&2
  exit 1
fi
if [[ -d $DESTINATION ]]; then
  cp -a -- "$DESTINATION" "$BACKUP"
  printf 'Backed up previous Omazen application copy: %s\n' "$BACKUP"
fi

mkdir -p -- "$DESTINATION" "$BIN_DIRECTORY"
for item in bin lib zen hooks vendor docs tests README.md CHANGELOG.md LICENSE THIRD_PARTY_LICENSES.md install.sh uninstall.sh; do
  [[ -e $SOURCE_ROOT/$item ]] || continue
  cp -a -- "$SOURCE_ROOT/$item" "$DESTINATION/"
done
printf '1.0.0\n' >"$DESTINATION/.omazen-installed"
chmod +x "$DESTINATION/bin/omazen" "$DESTINATION/hooks/theme-set" "$DESTINATION/install.sh" "$DESTINATION/uninstall.sh"

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
ln -sfn -- "$DESTINATION/bin/omazen" "$BIN_DIRECTORY/omazen"
printf 'Installed Omazen command: %s/omazen\n' "$BIN_DIRECTORY"

if [[ ${OMAZEN_INSTALL_NO_SETUP:-0} != 1 ]]; then
  "$DESTINATION/bin/omazen" setup
fi
