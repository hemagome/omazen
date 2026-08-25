#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

doctor_failures=0
doctor_warnings=0
doctor_checks=()
DOCTOR_JSON=0

doctor_json_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

doctor_color_enabled() {
  [[ -t 1 && ${TERM:-} != dumb && -z ${NO_COLOR:-} ]]
}

doctor_status() {
  local color=$1
  local label=$2
  shift 2

  if (( DOCTOR_JSON )); then
    doctor_checks+=(
      "{\"status\":\"$label\",\"message\":\"$(doctor_json_escape "$*")\"}"
    )
    return
  fi
  if doctor_color_enabled; then
    printf '\033[%sm[%s]\033[0m %s\n' "$color" "$label" "$*"
  else
    printf '[%s] %s\n' "$label" "$*"
  fi
}

doctor_pass() {
  doctor_status 32 PASS "$*"
}

doctor_warn() {
  doctor_status 33 WARN "$*"
  ((doctor_warnings += 1))
}

doctor_fail() {
  doctor_status 31 FAIL "$*"
  ((doctor_failures += 1))
}

doctor_provider_name() {
  if [[ $OMAZEN_SKIP_THEME_HOOK == 1 ]]; then
    printf 'external\n'
  else
    printf 'omarchy-hook\n'
  fi
}

doctor_active_theme_name() {
  read_state_line "$OMAZEN_THEME_NAME_FILE" 2>/dev/null || printf 'unknown\n'
}

doctor_emit_json() {
  local provider theme generated_at bridge_age ok index=0

  provider=$(doctor_provider_name)
  theme=$(doctor_active_theme_name)
  generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  bridge_age=${doctor_bridge_age:-}
  ok=false
  (( doctor_failures == 0 )) && ok=true

  printf '{\n'
  printf '  "schema_version": 1,\n'
  printf '  "ok": %s,\n' "$ok"
  printf '  "omazen_version": "%s",\n' "$(doctor_json_escape "$OMAZEN_VERSION")"
  printf '  "platform": "%s",\n' "$(doctor_json_escape "$doctor_platform")"
  printf '  "zen_version": "%s",\n' "$(doctor_json_escape "${doctor_zen_version:-unknown}")"
  printf '  "provider": "%s",\n' "$(doctor_json_escape "$provider")"
  printf '  "theme": "%s",\n' "$(doctor_json_escape "$theme")"
  printf '  "active_colors": "%s",\n' "$(doctor_json_escape "$OMAZEN_ACTIVE_COLORS")"
  printf '  "palette_file": "%s",\n' "$(doctor_json_escape "$OMAZEN_PALETTE_FILE")"
  printf '  "profiles_detected": %d,\n' "$doctor_profile_count"
  printf '  "bridge_version": "%s",\n' "$(doctor_json_escape "$doctor_bridge_version")"
  printf '  "bridge_last_event": "%s",\n' "$(doctor_json_escape "$doctor_bridge_timestamp")"
  if [[ -n $bridge_age ]]; then
    printf '  "bridge_last_event_age_seconds": %s,\n' "$bridge_age"
  else
    printf '  "bridge_last_event_age_seconds": null,\n'
  fi
  printf '  "bridge_logs": ['
  for index in "${!doctor_bridge_logs[@]}"; do
    (( index > 0 )) && printf ', '
    printf '"%s"' "$(doctor_json_escape "${doctor_bridge_logs[$index]}")"
  done
  printf '],\n'
  printf '  "failures": %d,\n' "$doctor_failures"
  printf '  "warnings": %d,\n' "$doctor_warnings"
  printf '  "generated_at": "%s",\n' "$generated_at"
  printf '  "checks": ['
  for index in "${!doctor_checks[@]}"; do
    (( index > 0 )) && printf ', '
    printf '%s' "${doctor_checks[$index]}"
  done
  printf ']\n'
  printf '}\n'
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

latest_bridge_timestamp() {
  awk '
    /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T/ { timestamp = $1 }
    END {
      if (timestamp != "") print timestamp
    }
  ' "$@"
}

latest_bridge_palette_application() {
  awk '
    /\[INFO\] PALETTE_APPLIED / {
      timestamp = $1
      accent = ""
      mode = ""
      profile = "legacy"
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^accent=/) accent = substr($i, 8)
        if ($i ~ /^mode=/) mode = substr($i, 6)
        if ($i ~ /^profile=/) profile = substr($i, 9)
      }
    }
    END {
      if (timestamp != "") print timestamp "|" accent "|" mode "|" profile
    }
  ' "$@"
}

latest_bridge_css_application() {
  awk '
    /\[INFO\] CHROME_CSS_APPLIED / {
      timestamp = $1
      primary = ""
      profile = "legacy"
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^primary=/) primary = substr($i, 9)
        if ($i ~ /^profile=/) profile = substr($i, 9)
      }
    }
    END {
      if (timestamp != "") print timestamp "|" primary "|" profile
    }
  ' "$@"
}

bridge_age_seconds() {
  local timestamp=$1
  local event_epoch now_epoch

  event_epoch=$(date -u -d "$timestamp" +%s 2>/dev/null) || return 1
  now_epoch=$(date -u +%s)
  if (( now_epoch >= event_epoch )); then
    printf '%s\n' "$((now_epoch - event_epoch))"
  else
    printf '0\n'
  fi
}

palette_json_value() {
  local key=$1
  awk -F'"' -v wanted="$key" '$2 == wanted { print $4; exit }' "$OMAZEN_PALETTE_FILE"
}

palette_diagnosis() {
  local border key actual expected
  local -A expected_keys=(
    [accent]=accent
    [background]=background
    [background_dark]=dark_background
    [background_light]=lighter_background
    [foreground]=foreground
    [foreground_muted]=muted
    [selection]=selection
  )

  if [[ -L $OMAZEN_PALETTE_FILE ]]; then
    printf 'palette file is a symbolic link: %s\n' "$OMAZEN_PALETTE_FILE"
    return 1
  fi
  if [[ ! -f $OMAZEN_PALETTE_FILE ]]; then
    printf 'palette file is missing: %s\n' "$OMAZEN_PALETTE_FILE"
    return 1
  fi
  if ! validate_palette_json "$OMAZEN_PALETTE_FILE"; then
    printf 'palette JSON is invalid or non-canonical: %s\n' "$OMAZEN_PALETTE_FILE"
    return 1
  fi
  if ! parse_colors_toml "$OMAZEN_ACTIVE_COLORS"; then
    printf 'active colors file is missing or invalid: %s\n' "$OMAZEN_ACTIVE_COLORS"
    return 1
  fi

  actual=$(palette_json_value mode)
  expected=${OMAZEN_TOML[mode]}
  if [[ $actual != "$expected" ]]; then
    printf 'mode mismatch: palette=%s, active=%s\n' "$actual" "$expected"
    return 1
  fi
  for key in "${!expected_keys[@]}"; do
    actual=$(palette_json_value "$key")
    expected=${OMAZEN_TOML[${expected_keys[$key]}],,}
    if [[ $actual != "$expected" ]]; then
      printf '%s mismatch: palette=%s, active=%s\n' "$key" "$actual" "$expected"
      return 1
    fi
  done
  border=$(palette_border)
  actual=$(palette_json_value border)
  if [[ $actual != "${border,,}" ]]; then
    printf 'border mismatch: palette=%s, active=%s\n' "$actual" "${border,,}"
    return 1
  fi
}

palette_matches_active_colors() {
  palette_diagnosis >/dev/null
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
  local platform version="" profile_count=0 profile hook last_error bridge_version
  local palette_reason palette_valid=0 disabled=0
  local palette_application css_application
  local applied_timestamp applied_accent applied_mode applied_profile
  local css_timestamp css_primary css_profile
  local current_accent current_mode bridge_timestamp bridge_age
  local bridge_logs=()
  doctor_failures=0
  doctor_warnings=0
  doctor_checks=()
  doctor_platform=""
  doctor_zen_version=""
  doctor_profile_count=0
  doctor_bridge_version=""
  doctor_bridge_timestamp=""
  doctor_bridge_age=""
  doctor_bridge_logs=()

  platform=$(platform_summary)
  doctor_platform=$platform
  if platform_is_supported; then
    doctor_pass "supported platform: $platform"
  else
    doctor_fail "unsupported platform: $platform; supported platform is Omarchy Quattro (4.x)"
  fi

  if [[ -d $OMAZEN_ZEN_PROGRAM_DIR && -f $OMAZEN_ZEN_PROGRAM_DIR/application.ini ]]; then
    doctor_pass "native Zen installation: $OMAZEN_ZEN_PROGRAM_DIR"
  else
    doctor_fail "supported native Zen installation not found"
  fi

  if version=$(detect_zen_version 2>/dev/null); then
    doctor_zen_version=$version
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
  doctor_profile_count=$profile_count
  (( profile_count > 0 )) || doctor_fail "no Zen profiles detected"

  if [[ $OMAZEN_SKIP_THEME_HOOK == 1 ]]; then
    doctor_pass "external palette provider mode (Omarchy hook not required)"
  else
    hook=$(hook_destination)
    doctor_exact_file "Omarchy theme-set hook" "$hook" "$OMAZEN_ROOT/hooks/theme-set" 1
    doctor_pass "active Omarchy theme: $(doctor_active_theme_name)"
  fi
  doctor_pass "active palette source: $OMAZEN_ACTIVE_COLORS"

  if palette_reason=$(palette_diagnosis); then
    palette_valid=1
    doctor_pass "normalized palette is valid, canonical, and current"
  else
    doctor_fail "normalized palette is missing, invalid, or stale: $OMAZEN_PALETTE_FILE ($palette_reason)"
  fi

  if [[ -e $OMAZEN_DISABLED_FILE ]]; then
    disabled=1
    doctor_warn "Omazen is disabled"
  else
    doctor_pass "Omazen is enabled"
  fi

  [[ -f $OMAZEN_BRIDGE_LOG_ARCHIVE ]] && bridge_logs+=("$OMAZEN_BRIDGE_LOG_ARCHIVE")
  [[ -f $OMAZEN_BRIDGE_LOG ]] && bridge_logs+=("$OMAZEN_BRIDGE_LOG")
  doctor_bridge_logs=("${bridge_logs[@]}")
  if (( ${#bridge_logs[@]} > 0 )); then
    bridge_version=$(latest_bridge_version "${bridge_logs[@]}")
    bridge_timestamp=$(latest_bridge_timestamp "${bridge_logs[@]}")
    bridge_age=$(bridge_age_seconds "$bridge_timestamp" 2>/dev/null || true)
  else
    bridge_version=""
    bridge_timestamp=""
    bridge_age=""
  fi
  doctor_bridge_version=$bridge_version
  doctor_bridge_timestamp=$bridge_timestamp
  doctor_bridge_age=$bridge_age
  if [[ $bridge_version == "$OMAZEN_VERSION" ]]; then
    doctor_pass "bridge $bridge_version has loaded in Zen"
  elif [[ -n $bridge_version ]]; then
    doctor_fail "loaded bridge version $bridge_version does not match Omazen $OMAZEN_VERSION"
  else
    doctor_warn "bridge has not logged a successful load yet; initial normal restart may still be pending"
  fi

  if (( disabled )); then
    doctor_pass "bridge palette application checks skipped while Omazen is disabled"
  elif (( palette_valid )); then
    current_accent=$(palette_json_value accent)
    current_mode=$(palette_json_value mode)
    palette_application=""
    css_application=""
    if (( ${#bridge_logs[@]} > 0 )); then
      palette_application=$(latest_bridge_palette_application "${bridge_logs[@]}")
      css_application=$(latest_bridge_css_application "${bridge_logs[@]}")
    fi
    if [[ -n $palette_application ]]; then
      IFS='|' read -r applied_timestamp applied_accent applied_mode applied_profile <<<"$palette_application"
      if [[ $applied_accent == "$current_accent" && $applied_mode == "$current_mode" ]]; then
        doctor_pass "bridge applied current palette accent=$current_accent mode=$current_mode profile=$applied_profile"
      else
        doctor_fail "bridge palette is stale: applied accent=$applied_accent mode=$applied_mode; current accent=$current_accent mode=$current_mode"
      fi
    else
      doctor_warn "bridge has not logged a palette application for the current palette yet"
    fi
    if [[ -n $css_application ]]; then
      IFS='|' read -r css_timestamp css_primary css_profile <<<"$css_application"
      if [[ $css_primary == "$current_accent" ]]; then
        doctor_pass "bridge CSS exposes current primary color $css_primary profile=$css_profile"
      else
        doctor_fail "bridge CSS is stale: applied primary=$css_primary; current accent=$current_accent"
      fi
    else
      doctor_warn "bridge has not logged a successful CSS probe for the current palette yet"
    fi
  else
    doctor_warn "bridge palette application checks skipped because the normalized palette is invalid"
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
  if [[ -n $bridge_timestamp ]]; then
    if [[ -n $bridge_age ]]; then
      doctor_pass "bridge log last event: $bridge_timestamp (age ${bridge_age}s)"
    else
      doctor_pass "bridge log last event: $bridge_timestamp"
    fi
  else
    doctor_warn "bridge log has no runtime events yet"
  fi

  if [[ -d $OMAZEN_HOME_DIR/.var/app/app.zen_browser.zen || -d $OMAZEN_HOME_DIR/.var/app/io.github.zen_browser.zen ]]; then
    doctor_warn "Flatpak Zen detected; Flatpak is outside this MVP because the sandbox blocks this backend"
  fi

  if (( DOCTOR_JSON )); then
    doctor_emit_json
  else
    printf '\nDoctor: %d failure(s), %d warning(s)\n' "$doctor_failures" "$doctor_warnings"
  fi
  (( doctor_failures == 0 ))
}
