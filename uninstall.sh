#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

set -euo pipefail

OMAZEN_HOME_DIR=${OMAZEN_HOME_DIR:-$HOME}
DESTINATION=${OMAZEN_DATA_DIR:-"${XDG_DATA_HOME:-$OMAZEN_HOME_DIR/.local/share}/omazen"}

if [[ -x $DESTINATION/bin/omazen ]]; then
  exec "$DESTINATION/bin/omazen" uninstall
fi

SOURCE_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
exec "$SOURCE_ROOT/bin/omazen" uninstall
