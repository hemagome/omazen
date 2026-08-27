#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

declare -Ag OMAZEN_TOML=()

parse_colors_toml() {
  local source=$1
  local line key value
  OMAZEN_TOML=()

  [[ -f $source ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*$ ]] && continue
    [[ $line =~ ^[[:space:]]*# ]] && continue
    if [[ $line =~ ^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*(#.*)?$ ]]; then
      key=${BASH_REMATCH[1]}
      value=${BASH_REMATCH[2]}
      OMAZEN_TOML["$key"]=$value
    fi
  done <"$source"

  [[ ${OMAZEN_TOML[mode]:-} == dark || ${OMAZEN_TOML[mode]:-} == light ]] || return 1
  for key in accent selection muted background dark_background lighter_background foreground; do
    [[ ${OMAZEN_TOML[$key]:-} =~ ^#[0-9A-Fa-f]{6}$ ]] || return 1
  done
}

palette_border() {
  if [[ ${OMAZEN_TOML[active_border_color]:-} =~ ^#[0-9A-Fa-f]{6}$ ]]; then
    printf '%s\n' "${OMAZEN_TOML[active_border_color]}"
  else
    printf '%s\n' "${OMAZEN_TOML[muted]}"
  fi
}

write_palette_json() {
  local destination=$1
  local temporary border
  border=$(palette_border)

  ensure_state_dir
  temporary=$(mktemp "$OMAZEN_STATE_DIR/.palette.json.XXXXXX")
  chmod 600 "$temporary"
  printf '{\n' >"$temporary"
  printf '  "schema_version": 1,\n' >>"$temporary"
  printf '  "mode": "%s",\n' "${OMAZEN_TOML[mode]}" >>"$temporary"
  printf '  "accent": "%s",\n' "${OMAZEN_TOML[accent],,}" >>"$temporary"
  printf '  "background": "%s",\n' "${OMAZEN_TOML[background],,}" >>"$temporary"
  printf '  "background_dark": "%s",\n' "${OMAZEN_TOML[dark_background],,}" >>"$temporary"
  printf '  "background_light": "%s",\n' "${OMAZEN_TOML[lighter_background],,}" >>"$temporary"
  printf '  "foreground": "%s",\n' "${OMAZEN_TOML[foreground],,}" >>"$temporary"
  printf '  "foreground_muted": "%s",\n' "${OMAZEN_TOML[muted],,}" >>"$temporary"
  printf '  "selection": "%s",\n' "${OMAZEN_TOML[selection],,}" >>"$temporary"
  printf '  "border": "%s"\n' "${border,,}" >>"$temporary"
  printf '}\n' >>"$temporary"
  mv -f -- "$temporary" "$destination"
}

validate_palette_json() {
  local source=$1
  [[ -f $source ]] || return 1
  LC_ALL=C awk '
    {
      bytes += length($0) + length(RT)
      if (RT == "\n") newline_count++
      lines[NR] = $0
      if ($0 ~ /^  "[a-z_]+":/) key_count++
      if ($0 == "  \"schema_version\": 1,") schema_count++
      if ($0 ~ /^  "mode": "(dark|light)",$/) mode_count++
      if ($0 ~ /^  "accent": "#[0-9a-f]{6}",$/) accent_count++
      if ($0 ~ /^  "background": "#[0-9a-f]{6}",$/) background_count++
      if ($0 ~ /^  "background_dark": "#[0-9a-f]{6}",$/) background_dark_count++
      if ($0 ~ /^  "background_light": "#[0-9a-f]{6}",$/) background_light_count++
      if ($0 ~ /^  "foreground": "#[0-9a-f]{6}",$/) foreground_count++
      if ($0 ~ /^  "foreground_muted": "#[0-9a-f]{6}",$/) foreground_muted_count++
      if ($0 ~ /^  "selection": "#[0-9a-f]{6}",$/) selection_count++
      if ($0 ~ /^  "border": "#[0-9a-f]{6}"$/) border_count++
    }
    END {
      valid = bytes <= 2048 && NR == 12 && newline_count == 12 &&
        lines[1] == "{" && lines[NR] == "}" &&
        schema_count > 0 && mode_count > 0 && accent_count > 0 &&
        background_count > 0 && background_dark_count > 0 &&
        background_light_count > 0 && foreground_count > 0 &&
        foreground_muted_count > 0 && selection_count > 0 &&
        border_count > 0 && key_count == 10
      exit !valid
    }
  ' "$source"
}

sync_palette() {
  parse_colors_toml "$OMAZEN_ACTIVE_COLORS" || \
    die "invalid or missing Quattro palette: $OMAZEN_ACTIVE_COLORS"
  write_palette_json "$OMAZEN_PALETTE_FILE"
  say "Palette synchronized atomically: $OMAZEN_PALETTE_FILE"
}
