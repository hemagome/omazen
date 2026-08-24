#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

doctor_failures=0
doctor_warnings=0

doctor_pass() {
  printf '[PASS] %s\n' "$*"
}

doctor_warn() {
  printf '[WARN] %s\n' "$*"
  ((doctor_warnings += 1))
}

doctor_fail() {
  printf '[FAIL] %s\n' "$*"
  ((doctor_failures += 1))
}

doctor_exact_file() {
  local label=$1
  local installed=$2
  local expected=$3
  local executable=${4:-0}
  local mode

  if [[ -L $installed ]]; then
    doctor_fail "$label is a symbolic link: $installed"
    return
  fi
  if [[ ! -f $installed ]]; then
    doctor_fail "$label is missing: $installed"
    return
  fi
  if [[ ! -f $expected ]] || ! cmp -s -- "$installed" "$expected"; then
    doctor_fail "$label is modified or outdated: $installed"
    return
  fi
  mode=$(stat -c '%a' -- "$installed" 2>/dev/null || true)
  if [[ ! $mode =~ ^[0-7]{3,4}$ ]] || (( (8#$mode & 8#022) != 0 )); then
    doctor_fail "$label has unsafe group/world write permissions: $installed"
    return
  fi
  if (( executable )) && [[ ! -x $installed ]]; then
    doctor_fail "$label is not executable: $installed"
    return
  fi
  doctor_pass "$label integrity: $installed"
}

current_bridge_error() {
  awk '
    /\[ERROR\]/ {
      error = $0
      next
    }
    /\[INFO\] (BRIDGE_LOADED|PALETTE_APPLIED|CHROME_CSS_APPLIED|DISABLED)( |$)/ {
      error = ""
    }
    END {
      if (error != "") print error
    }
  ' "$@"
}

latest_bridge_version() {
  awk '
    /\[INFO\] BRIDGE_LOADED version=/ {
      line = $0
      sub(/^.*BRIDGE_LOADED version=/, "", line)
      sub(/[[:space:]].*$/, "", line)
      version = line
    }
    END {
      if (version != "") print version
    }
  ' "$@"
}

palette_matches_active_colors() {
  local border key
  local -A expected=(
    [accent]=accent
    [background]=background
    [background_dark]=dark_background
    [background_light]=lighter_background
    [foreground]=foreground
    [foreground_muted]=muted
    [selection]=selection
  )

  validate_palette_json "$OMAZEN_PALETTE_FILE" || return 1
  parse_colors_toml "$OMAZEN_ACTIVE_COLORS" || return 1
  grep -Fqx -- "  \"mode\": \"${OMAZEN_TOML[mode]}\"," "$OMAZEN_PALETTE_FILE" || return 1
  for key in "${!expected[@]}"; do
    grep -Fqx -- "  \"$key\": \"${OMAZEN_TOML[${expected[$key]}],,}\"," \
      "$OMAZEN_PALETTE_FILE" || return 1
  done
  border=$(palette_border)
  grep -Fqx -- "  \"border\": \"${border,,}\"" "$OMAZEN_PALETTE_FILE"
}

doctor_profile() {
  local profile=$1
  local relative
  if profile_has_compatible_fx "$profile"; then
    doctor_pass "fx-autoconfig profile runtime: $profile"
  else
    doctor_fail "fx-autoconfig profile runtime missing or incompatible: $profile"
  fi
  for relative in "${OMAZEN_PROFILE_FILES[@]}"; do
    doctor_exact_file \
      "profile file $relative" \
      "$profile/chrome/JS/$relative" \
      "$OMAZEN_ROOT/zen/$relative"
  done
}

doctor_omazen() {
  local version profile_count=0 profile hook last_error bridge_version
  local bridge_logs=()
  doctor_failures=0
  doctor_warnings=0

  if [[ -d $OMAZEN_ZEN_PROGRAM_DIR && -f $OMAZEN_ZEN_PROGRAM_DIR/application.ini ]]; then
    doctor_pass "native Zen installation: $OMAZEN_ZEN_PROGRAM_DIR"
  else
    doctor_fail "supported native Zen installation not found"
  fi

  if version=$(detect_zen_version 2>/dev/null); then
    if [[ $version == 1.21.15b ]]; then
      doctor_pass "Zen $version (fully validated version)"
    elif version_at_least "$version" "1.20"; then
      doctor_warn "Zen $version is a compatible candidate but has not been fully validated by this release"
    else
      doctor_fail "Zen $version is below the minimum candidate version 1.20"
    fi
  else
    doctor_fail "Zen version could not be detected"
  fi

  if program_has_compatible_fx; then
    doctor_pass "fx-autoconfig program loader"
  else
    doctor_fail "fx-autoconfig program loader missing or conflicting"
  fi
  doctor_exact_file \
    "required experimental WindowActor preference" \
    "$OMAZEN_ZEN_PROGRAM_DIR/defaults/pref/omazen-prefs.js" \
    "$OMAZEN_ROOT/zen/omazen-prefs.js"

  while IFS= read -r profile; do
    ((profile_count += 1))
    doctor_profile "$profile"
  done < <(zen_profiles)
  (( profile_count > 0 )) || doctor_fail "no Zen profiles detected"

  hook=$(hook_destination)
  doctor_exact_file "Omarchy theme-set hook" "$hook" "$OMAZEN_ROOT/hooks/theme-set" 1

  if palette_matches_active_colors; then
    doctor_pass "normalized palette is valid, canonical, and current"
  else
    doctor_fail "normalized palette is missing, invalid, or stale: $OMAZEN_PALETTE_FILE"
  fi

  if [[ -e $OMAZEN_DISABLED_FILE ]]; then
    doctor_warn "Omazen is disabled"
  else
    doctor_pass "Omazen is enabled"
  fi

  bridge_version=""
  [[ -f $OMAZEN_BRIDGE_LOG_ARCHIVE ]] && bridge_logs+=("$OMAZEN_BRIDGE_LOG_ARCHIVE")
  [[ -f $OMAZEN_BRIDGE_LOG ]] && bridge_logs+=("$OMAZEN_BRIDGE_LOG")
  if (( ${#bridge_logs[@]} > 0 )); then
    bridge_version=$(latest_bridge_version "${bridge_logs[@]}")
  fi
  if [[ $bridge_version == "$OMAZEN_VERSION" ]]; then
    doctor_pass "bridge $bridge_version has loaded in Zen"
  elif [[ -n $bridge_version ]]; then
    doctor_fail "loaded bridge version $bridge_version does not match Omazen $OMAZEN_VERSION"
  else
    doctor_warn "bridge has not logged a successful load yet; initial normal restart may still be pending"
  fi

  last_error=""
  if (( ${#bridge_logs[@]} > 0 )); then
    last_error=$(current_bridge_error "${bridge_logs[@]}")
  fi
  if [[ -n $last_error ]]; then
    doctor_fail "current bridge error: $last_error"
  else
    doctor_pass "no current bridge error recorded"
  fi

  if [[ -d $OMAZEN_HOME_DIR/.var/app/app.zen_browser.zen || -d $OMAZEN_HOME_DIR/.var/app/io.github.zen_browser.zen ]]; then
    doctor_warn "Flatpak Zen detected; Flatpak is outside this MVP because the sandbox blocks this backend"
  fi

  printf '\nDoctor: %d failure(s), %d warning(s)\n' "$doctor_failures" "$doctor_warnings"
  (( doctor_failures == 0 ))
}
