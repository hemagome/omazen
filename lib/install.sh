#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

OMAZEN_PROFILE_FILES=(
  omazen-bridge.uc.js
  Omazen/OmazenParent.sys.mjs
  Omazen/OmazenChild.sys.mjs
  Omazen/OmazenPalette.sys.mjs
  "Omazen/omazen-chrome-v${OMAZEN_VERSION}.css"
  "Omazen/omazen-content-v${OMAZEN_VERSION}.css"
)

program_has_compatible_fx() {
  local config="$OMAZEN_ZEN_PROGRAM_DIR/config.js"
  [[ -f $config ]] || return 1
  grep -Fq 'chrome://userchromejs/content/boot.sys.mjs' "$config" || return 1
  grep -RqsF 'general.config.filename", "config.js"' "$OMAZEN_ZEN_PROGRAM_DIR/defaults/pref"
}

program_has_any_autoconfig() {
  [[ -f $OMAZEN_ZEN_PROGRAM_DIR/config.js ]] || \
    grep -RqsF 'general.config.filename' "$OMAZEN_ZEN_PROGRAM_DIR/defaults/pref" 2>/dev/null
}

install_program_loader() {
  local vendor="$OMAZEN_ROOT/vendor/fx-autoconfig"
  local config="$OMAZEN_ZEN_PROGRAM_DIR/config.js"
  local prefs="$OMAZEN_ZEN_PROGRAM_DIR/defaults/pref/config-prefs.js"
  local omazen_prefs="$OMAZEN_ZEN_PROGRAM_DIR/defaults/pref/omazen-prefs.js"

  if program_has_compatible_fx; then
    say "Reusing compatible fx-autoconfig program loader."
  elif program_has_any_autoconfig; then
    die "Zen already has a different autoconfig setup; Omazen will not merge or overwrite it"
  else
    install_program_file "$vendor/program/config.js" "$config"
    install_program_file "$vendor/program/defaults/pref/config-prefs.js" "$prefs"
  fi
  install_program_file "$OMAZEN_ROOT/zen/omazen-prefs.js" "$omazen_prefs"
}

install_fx_profile_runtime() {
  local profile=$1
  local source_dir="$OMAZEN_ROOT/vendor/fx-autoconfig/profile/chrome/utils"
  local destination_dir="$profile/chrome/utils"
  local name

  if profile_has_compatible_fx "$profile"; then
    say "Reusing compatible fx-autoconfig profile runtime: $profile"
    return 0
  fi
  if profile_has_any_fx "$profile"; then
    fx_profile_runtime_is_repairable "$profile" || \
      die "partial or incompatible unowned fx-autoconfig runtime in profile: $profile"
    say "Repairing partial fx-autoconfig profile runtime: $profile"
  fi
  for name in "${FX_UTIL_FILES[@]}"; do
    install_user_file "$source_dir/$name" "$destination_dir/$name"
  done
}

fx_profile_runtime_is_repairable() {
  local profile=$1
  local source_dir="$OMAZEN_ROOT/vendor/fx-autoconfig/profile/chrome/utils"
  local destination_dir="$profile/chrome/utils"
  local name source destination source_hash destination_hash

  for name in "${FX_UTIL_FILES[@]}"; do
    source="$source_dir/$name"
    destination="$destination_dir/$name"
    [[ -e $destination ]] || continue
    [[ -f $destination ]] || return 1
    source_hash=$(sha256_file "$source")
    destination_hash=$(sha256_file "$destination")
    [[ $source_hash == "$destination_hash" ]] && continue
    manifest_has_path "$OMAZEN_PROFILE_MANIFEST" "$destination" || return 1
  done
  return 0
}

install_omazen_profile_files() {
  local profile=$1
  local relative
  for relative in "${OMAZEN_PROFILE_FILES[@]}"; do
    install_user_file "$OMAZEN_ROOT/zen/$relative" "$profile/chrome/JS/$relative"
  done
}

cleanup_obsolete_profile_styles() {
  local profile=$1
  local current_chrome="$profile/chrome/JS/Omazen/omazen-chrome-v${OMAZEN_VERSION}.css"
  local current_content="$profile/chrome/JS/Omazen/omazen-content-v${OMAZEN_VERSION}.css"
  local style

  while IFS= read -r style; do
    [[ $style == "$current_chrome" || $style == "$current_content" ]] && continue
    if manifest_has_path "$OMAZEN_PROFILE_MANIFEST" "$style"; then
      if ! remove_owned_user_file "$OMAZEN_PROFILE_MANIFEST" "$style"; then
        warn "obsolete stylesheet was modified and remains installed: $style"
      fi
    fi
  done < <(
    find "$profile/chrome/JS/Omazen" -maxdepth 1 -type f \
      \( -name 'omazen-chrome.css' -o -name 'omazen-chrome-v*.css' \
         -o -name 'omazen-content.css' -o -name 'omazen-content-v*.css' \) -print 2>/dev/null
  )
}

check_supported_install() {
  [[ -d $OMAZEN_ZEN_PROGRAM_DIR ]] || die "supported Zen program directory not found: $OMAZEN_ZEN_PROGRAM_DIR"
  [[ -f $OMAZEN_ZEN_PROGRAM_DIR/application.ini ]] || die "Zen application.ini not found in supported installation"
  if [[ ${OMAZEN_SKIP_PACKAGE_CHECK:-0} != 1 ]]; then
    pacman -Q zen-browser-bin >/dev/null 2>&1 || die "MVP supports the native zen-browser-bin package only"
  fi
}

setup_omazen() {
  local profile_count=0
  local profile version
  local profiles=()

  ensure_state_dir
  check_supported_install
  version=$(detect_zen_version) || die "could not determine Zen version"
  version_at_least "$version" "1.20" || die "Zen $version is older than the minimum candidate version 1.20"
  mapfile -t profiles < <(zen_profiles)
  (( ${#profiles[@]} > 0 )) || die "no Zen profiles found in $OMAZEN_ZEN_CONFIG_DIR/profiles.ini"

  install_program_loader
  for profile in "${profiles[@]}"; do
    ((profile_count += 1))
    install_fx_profile_runtime "$profile"
    install_omazen_profile_files "$profile"
    cleanup_obsolete_profile_styles "$profile"
  done

  if [[ $OMAZEN_SKIP_THEME_HOOK == 1 ]]; then
    say "Skipping the Omarchy theme hook for an external palette provider."
  else
    install_theme_hook
  fi
  sync_palette
  rm -f -- "$OMAZEN_DISABLED_FILE"

  say "Omazen setup complete for $profile_count profile(s)."
  say "Close Zen normally and open it once to activate the privileged loader."
  say "Security note: profile chrome scripts can execute with browser privileges; see docs/security.md."
}

other_user_scripts_exist() {
  local profile file
  while IFS= read -r profile; do
    [[ -d $profile/chrome/JS ]] || continue
    while IFS= read -r file; do
      case "$file" in
        */omazen-bridge.uc.js|*/Omazen/*) ;;
        *) return 0 ;;
      esac
    done < <(find "$profile/chrome/JS" -type f \( -name '*.uc.js' -o -name '*.uc.mjs' -o -name '*.sys.mjs' \) -print 2>/dev/null)
  done < <(zen_profiles)
  return 1
}

remove_manifest_user_files() {
  local manifest=$1
  local path _hash
  local failed=0
  [[ -f $manifest ]] || return 0
  while IFS='|' read -r path _hash; do
    [[ -n $path ]] || continue
    remove_owned_user_file "$manifest" "$path" || failed=1
  done < <(tac "$manifest")
  return "$failed"
}

remove_manifest_program_files() {
  local path _hash
  local failed=0
  [[ -f $OMAZEN_PROGRAM_MANIFEST ]] || return 0
  while IFS='|' read -r path _hash; do
    [[ -n $path ]] || continue
    if [[ $path == "$OMAZEN_ZEN_PROGRAM_DIR/config.js" || $path == "$OMAZEN_ZEN_PROGRAM_DIR/defaults/pref/config-prefs.js" ]]; then
      if other_user_scripts_exist; then
        warn "leaving shared fx-autoconfig program loader because other user scripts exist"
        continue
      fi
    fi
    remove_owned_program_file "$path" || failed=1
  done < <(tac "$OMAZEN_PROGRAM_MANIFEST")
  return "$failed"
}

cleanup_empty_integration_dirs() {
  local profile
  while IFS= read -r profile; do
    rmdir -- "$profile/chrome/JS/Omazen" 2>/dev/null || true
    rmdir -- "$profile/chrome/JS" 2>/dev/null || true
    rmdir -- "$profile/chrome/utils" 2>/dev/null || true
    rmdir -- "$profile/chrome" 2>/dev/null || true
  done < <(zen_profiles)
  rmdir -- "$OMAZEN_HOOKS_DIR/theme-set.d" 2>/dev/null || true
}

uninstall_omazen() {
  local leftovers=0

  remove_manifest_user_files "$OMAZEN_HOOK_MANIFEST" || leftovers=1
  remove_manifest_user_files "$OMAZEN_PROFILE_MANIFEST" || leftovers=1
  remove_manifest_program_files || leftovers=1
  cleanup_empty_integration_dirs

  rm -f -- \
    "$OMAZEN_DISABLED_FILE" \
    "$OMAZEN_PALETTE_FILE" \
    "$OMAZEN_BRIDGE_LOG" \
    "$OMAZEN_BRIDGE_LOG_ARCHIVE"
  if (( leftovers == 0 )); then
    rm -f -- "$OMAZEN_HOOK_MANIFEST" "$OMAZEN_PROFILE_MANIFEST" "$OMAZEN_PROGRAM_MANIFEST"
    rmdir -- "$OMAZEN_OWNED_DIR" 2>/dev/null || true
    rmdir -- "$OMAZEN_BACKUP_DIR" 2>/dev/null || true
    rmdir -- "$OMAZEN_STATE_DIR" 2>/dev/null || true
    say "Omazen integration removed. Existing userChrome.css, userContent.css and user.js were not touched."
  else
    warn "uninstall left modified or shared files in place; ownership records remain in $OMAZEN_OWNED_DIR"
    return 1
  fi
}
