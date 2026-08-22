#!/bin/bash

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

doctor_profile() {
  local profile=$1
  local relative
  if profile_has_compatible_fx "$profile"; then
    doctor_pass "fx-autoconfig profile runtime: $profile"
  else
    doctor_fail "fx-autoconfig profile runtime missing or incompatible: $profile"
  fi
  for relative in "${OMAZEN_PROFILE_FILES[@]}"; do
    if [[ -f $profile/chrome/JS/$relative ]]; then
      doctor_pass "profile file: $relative"
    else
      doctor_fail "missing profile file: $profile/chrome/JS/$relative"
    fi
  done
}

doctor_omazen() {
  local version profile_count=0 profile hook last_error
  doctor_failures=0
  doctor_warnings=0

  if [[ -d $OMAZEN_ZEN_PROGRAM_DIR && -f $OMAZEN_ZEN_PROGRAM_DIR/application.ini ]]; then
    doctor_pass "native Zen installation: $OMAZEN_ZEN_PROGRAM_DIR"
  else
    doctor_fail "supported native Zen installation not found"
  fi

  if version=$(detect_zen_version 2>/dev/null); then
    if [[ $version == 1.21.15b ]]; then
      doctor_pass "Zen $version (PoC-tested version)"
    elif version_at_least "$version" "1.20"; then
      doctor_warn "Zen $version is a compatible candidate but has not been PoC-tested by this release"
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
  if [[ -f $OMAZEN_ZEN_PROGRAM_DIR/defaults/pref/omazen-prefs.js ]]; then
    doctor_pass "required experimental WindowActor preference"
  else
    doctor_fail "missing Omazen preference drop-in"
  fi

  while IFS= read -r profile; do
    ((profile_count += 1))
    doctor_profile "$profile"
  done < <(zen_profiles)
  (( profile_count > 0 )) || doctor_fail "no Zen profiles detected"

  hook=$(hook_destination)
  if [[ -f $hook ]]; then
    doctor_pass "Omarchy theme-set hook: $hook"
  else
    doctor_fail "Omarchy theme-set hook missing: $hook"
  fi

  if validate_palette_json "$OMAZEN_PALETTE_FILE"; then
    doctor_pass "normalized palette is valid and canonical"
  else
    doctor_fail "normalized palette is missing or invalid: $OMAZEN_PALETTE_FILE"
  fi

  if [[ -e $OMAZEN_DISABLED_FILE ]]; then
    doctor_warn "Omazen is disabled"
  else
    doctor_pass "Omazen is enabled"
  fi

  if [[ -f $OMAZEN_BRIDGE_LOG ]] && grep -Fq 'BRIDGE_LOADED' "$OMAZEN_BRIDGE_LOG"; then
    doctor_pass "bridge has loaded in Zen"
  else
    doctor_warn "bridge has not logged a successful load yet; initial normal restart may still be pending"
  fi

  last_error=""
  if [[ -f $OMAZEN_BRIDGE_LOG ]]; then
    last_error=$(grep -F '[ERROR]' "$OMAZEN_BRIDGE_LOG" | tail -n 1 || true)
  fi
  if [[ -n $last_error ]]; then
    doctor_warn "last bridge error: $last_error"
  else
    doctor_pass "no bridge error recorded"
  fi

  if [[ -d $OMAZEN_HOME_DIR/.var/app/app.zen_browser.zen || -d $OMAZEN_HOME_DIR/.var/app/io.github.zen_browser.zen ]]; then
    doctor_warn "Flatpak Zen detected; Flatpak is outside this MVP because the sandbox blocks this backend"
  fi

  printf '\nDoctor: %d failure(s), %d warning(s)\n' "$doctor_failures" "$doctor_warnings"
  (( doctor_failures == 0 ))
}

