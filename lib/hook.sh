#!/bin/bash

hook_destination() {
  printf '%s\n' "$OMAZEN_HOOKS_DIR/theme-set.d/theme-set"
}

install_theme_hook() {
  local source="$OMAZEN_ROOT/hooks/theme-set"
  local destination
  local source_hash destination_hash
  destination=$(hook_destination)
  source_hash=$(sha256_file "$source")

  if [[ -f $destination ]]; then
    destination_hash=$(sha256_file "$destination")
    if [[ $destination_hash == "$source_hash" ]]; then
      say "Reusing identical Omarchy hook: $destination"
      return 0
    fi
    if ! manifest_has_path "$OMAZEN_HOOK_MANIFEST" "$destination"; then
      die "refusing to overwrite unowned Omarchy hook: $destination"
    fi
    backup_owned_file "$destination"
  fi

  if [[ ${OMAZEN_TESTING:-0} == 1 ]]; then
    mkdir -p -- "$(dirname -- "$destination")"
    install -m 0755 -- "$source" "$destination"
  else
    require_command omarchy
    omarchy hook install theme-set "$source"
  fi
  record_owned_file "$OMAZEN_HOOK_MANIFEST" "$destination" "$source_hash"
}

