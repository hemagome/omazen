#!/bin/bash

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
  local color_key
  [[ -f $source ]] || return 1
  [[ $(wc -c <"$source") -le 2048 ]] || return 1
  [[ $(wc -l <"$source") -eq 12 ]] || return 1
  [[ $(head -n 1 "$source") == "{" && $(tail -n 1 "$source") == "}" ]] || return 1
  grep -Eq '^  "schema_version": 1,$' "$source" || return 1
  grep -Eq '^  "mode": "(dark|light)",$' "$source" || return 1
  for color_key in accent background background_dark background_light foreground foreground_muted selection; do
    grep -Eq "^  \"$color_key\": \"#[0-9a-f]{6}\",$" "$source" || return 1
  done
  grep -Eq '^  "border": "#[0-9a-f]{6}"$' "$source" || return 1
  [[ $(grep -Ec '^  "[a-z_]+":' "$source") -eq 10 ]] || return 1
}

sync_palette() {
  parse_colors_toml "$OMAZEN_ACTIVE_COLORS" || \
    die "invalid or missing Quattro palette: $OMAZEN_ACTIVE_COLORS"
  write_palette_json "$OMAZEN_PALETTE_FILE"
  validate_palette_json "$OMAZEN_PALETTE_FILE" || die "generated palette failed validation"
  say "Palette synchronized atomically: $OMAZEN_PALETTE_FILE"
}
