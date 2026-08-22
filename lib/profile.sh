#!/bin/bash

zen_profiles() {
  local profiles_ini="$OMAZEN_ZEN_CONFIG_DIR/profiles.ini"
  local profile canonical config_canonical

  if [[ -n ${OMAZEN_PROFILE:-} ]]; then
    [[ -d $OMAZEN_PROFILE ]] && printf '%s\n' "$(realpath -m -- "$OMAZEN_PROFILE")"
    return
  fi
  [[ -f $profiles_ini ]] || return 0

  config_canonical=$(realpath -m -- "$OMAZEN_ZEN_CONFIG_DIR")
  while IFS= read -r profile; do
    [[ -n $profile ]] || continue
    canonical=$(realpath -m -- "$profile")
    if [[ $profile == "$OMAZEN_ZEN_CONFIG_DIR/"* && $canonical != "$config_canonical/"* ]]; then
      warn "ignoring profile path escaping Zen config root: $profile"
      continue
    fi
    [[ -d $canonical ]] && printf '%s\n' "$canonical"
  done < <(
    awk -v root="$OMAZEN_ZEN_CONFIG_DIR" '
      function emit() {
        if (section ~ /^\[Profile[0-9]+\]$/ && path != "") {
          if (relative == "1") print root "/" path
          else print path
        }
      }
      /^\[/ { emit(); section=$0; path=""; relative=""; next }
      /^Path=/ { path=substr($0, 6); next }
      /^IsRelative=/ { relative=substr($0, 12); next }
      END { emit() }
    ' "$profiles_ini"
  )
}

detect_zen_version() {
  local application_ini="$OMAZEN_ZEN_PROGRAM_DIR/application.ini"
  if [[ -n ${OMAZEN_ZEN_VERSION_OVERRIDE:-} ]]; then
    printf '%s\n' "$OMAZEN_ZEN_VERSION_OVERRIDE"
  elif [[ -f $application_ini ]]; then
    awk -F= '$1 == "Version" { print $2; exit }' "$application_ini"
  elif command -v zen-browser >/dev/null 2>&1; then
    zen-browser --version | awk '{print $NF}'
  else
    return 1
  fi
}

zen_version_number() {
  local version=${1#v}
  version=${version%%[!0-9.]*}
  printf '%s\n' "$version"
}

version_at_least() {
  local have wanted
  have=$(zen_version_number "$1")
  wanted=$(zen_version_number "$2")
  [[ -n $have && -n $wanted && $(printf '%s\n%s\n' "$wanted" "$have" | sort -V | head -n 1) == "$wanted" ]]
}

profile_has_compatible_fx() {
  local profile=$1
  local boot="$profile/chrome/utils/boot.sys.mjs"
  local manifest="$profile/chrome/utils/chrome.manifest"
  [[ -f $boot && -f $manifest ]] || return 1
  grep -Fq 'buildScriptActorDefinition' "$boot" && \
    grep -Fq 'content userscripts' "$manifest"
}

profile_has_any_fx() {
  local profile=$1
  [[ -f $profile/chrome/utils/boot.sys.mjs || -f $profile/chrome/utils/chrome.manifest ]]
}

