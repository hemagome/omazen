#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# See NOTICE for the required Omazen project attribution terms.

OMAZEN_VERSION=$(<"$OMAZEN_ROOT/VERSION")
[[ $OMAZEN_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'ERROR: invalid Omazen VERSION file\n' >&2
  exit 1
}
OMAZEN_HOME_DIR=${OMAZEN_HOME_DIR:-$HOME}
OMAZEN_STATE_DIR=${OMAZEN_STATE_DIR:-"${XDG_STATE_HOME:-$OMAZEN_HOME_DIR/.local/state}/omazen"}
OMAZEN_PALETTE_FILE="$OMAZEN_STATE_DIR/palette.json"
OMAZEN_DISABLED_FILE="$OMAZEN_STATE_DIR/disabled"
OMAZEN_BRIDGE_LOG="$OMAZEN_STATE_DIR/bridge.log"
OMAZEN_BRIDGE_LOG_ARCHIVE="$OMAZEN_STATE_DIR/bridge.log.1"
OMAZEN_OWNED_DIR="$OMAZEN_STATE_DIR/owned"
OMAZEN_BACKUP_DIR="$OMAZEN_STATE_DIR/backups"
OMAZEN_PROFILE_MANIFEST="$OMAZEN_OWNED_DIR/profile-files"
OMAZEN_PROGRAM_MANIFEST="$OMAZEN_OWNED_DIR/program-files"
OMAZEN_HOOK_MANIFEST="$OMAZEN_OWNED_DIR/hook-files"
OMAZEN_ZEN_CONFIG_DIR=${OMAZEN_ZEN_CONFIG_DIR:-"${XDG_CONFIG_HOME:-$OMAZEN_HOME_DIR/.config}/zen"}
OMAZEN_ZEN_PROGRAM_DIR=${OMAZEN_ZEN_PROGRAM_DIR:-/opt/zen-browser-bin}
OMAZEN_HOOKS_DIR=${OMAZEN_HOOKS_DIR:-"${XDG_CONFIG_HOME:-$OMAZEN_HOME_DIR/.config}/omarchy/hooks"}
OMAZEN_ACTIVE_COLORS=${OMAZEN_ACTIVE_COLORS:-"${XDG_STATE_HOME:-$OMAZEN_HOME_DIR/.local/state}/omarchy/current/theme/colors.toml"}
OMAZEN_SKIP_THEME_HOOK=${OMAZEN_SKIP_THEME_HOOK-0}
[[ $OMAZEN_SKIP_THEME_HOOK == 0 || $OMAZEN_SKIP_THEME_HOOK == 1 ]] || {
  printf 'ERROR: OMAZEN_SKIP_THEME_HOOK must be 0 or 1\n' >&2
  exit 1
}
OMAZEN_DATA_DIR=${OMAZEN_DATA_DIR:-"${XDG_DATA_HOME:-$OMAZEN_HOME_DIR/.local/share}/omazen"}
OMAZEN_LOCAL_BIN_DIR=${OMAZEN_LOCAL_BIN_DIR:-"${XDG_BIN_HOME:-$OMAZEN_HOME_DIR/.local/bin}"}
OMAZEN_OS_RELEASE_FILE=${OMAZEN_OS_RELEASE_FILE:-/etc/os-release}

os_release_value() {
  local key=$1
  [[ -r $OMAZEN_OS_RELEASE_FILE ]] || return 1
  awk -F= -v wanted="$key" '
    $1 == wanted {
      value = substr($0, index($0, "=") + 1)
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      sub(/^\047/, "", value)
      sub(/\047$/, "", value)
      print value
      exit
    }
  ' "$OMAZEN_OS_RELEASE_FILE"
}

platform_id() {
  os_release_value ID 2>/dev/null || printf 'unknown\n'
}

platform_name() {
  local name
  name=$(os_release_value PRETTY_NAME 2>/dev/null || true)
  [[ -n $name ]] || name=$(os_release_value NAME 2>/dev/null || true)
  printf '%s\n' "${name:-unknown}"
}

platform_version() {
  local version
  version=$(os_release_value VERSION_ID 2>/dev/null || true)
  [[ -n $version ]] || version=$(os_release_value BUILD_ID 2>/dev/null || true)
  printf '%s\n' "${version:-unknown}"
}

platform_major_version() {
  local version
  version=$(platform_version)
  [[ $version =~ ^([0-9]+)([.]|$) ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

platform_summary() {
  local id name version
  id=$(platform_id)
  name=$(platform_name)
  version=$(platform_version)
  if [[ $version != unknown && $name != *"$version"* ]]; then
    name="$name $version"
  fi
  printf '%s (%s)\n' "$name" "$id"
}

platform_is_supported() {
  local id major
  id=$(platform_id)
  major=$(platform_major_version) || return 1
  [[ $id == omarchy && $major == 4 ]]
}

say() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

ensure_state_dir() {
  umask 077
  mkdir -p -- "$OMAZEN_STATE_DIR" "$OMAZEN_OWNED_DIR" "$OMAZEN_BACKUP_DIR"
  chmod 700 "$OMAZEN_STATE_DIR" "$OMAZEN_OWNED_DIR" "$OMAZEN_BACKUP_DIR"
}

manifest_hash_for() {
  local manifest=$1
  local path=$2
  [[ -f $manifest ]] || return 1
  awk -F '|' -v wanted="$path" '$1 == wanted { print $2; found=1 } END { if (!found) exit 1 }' "$manifest"
}

manifest_has_path() {
  manifest_hash_for "$1" "$2" >/dev/null 2>&1
}

record_owned_file() {
  local manifest=$1
  local path=$2
  local hash=$3
  local temporary

  ensure_state_dir
  temporary=$(mktemp "$OMAZEN_OWNED_DIR/.manifest.XXXXXX")
  if [[ -f $manifest ]]; then
    awk -F '|' -v wanted="$path" '$1 != wanted' "$manifest" >"$temporary"
  fi
  printf '%s|%s\n' "$path" "$hash" >>"$temporary"
  chmod 600 "$temporary"
  mv -f -- "$temporary" "$manifest"
}

forget_owned_file() {
  local manifest=$1
  local path=$2
  local temporary

  [[ -f $manifest ]] || return 0
  temporary=$(mktemp "$OMAZEN_OWNED_DIR/.manifest.XXXXXX")
  awk -F '|' -v wanted="$path" '$1 != wanted' "$manifest" >"$temporary"
  chmod 600 "$temporary"
  mv -f -- "$temporary" "$manifest"
}

backup_owned_file() {
  local path=$1
  local relative=${path#/}
  local destination="$OMAZEN_BACKUP_DIR/$(date -u +%Y%m%dT%H%M%SZ)/$relative"

  [[ -f $path ]] || return 0
  mkdir -p -- "$(dirname -- "$destination")"
  cp -a -- "$path" "$destination"
  say "Backed up owned file: $destination"
}

run_privileged() {
  if [[ ${OMAZEN_TESTING:-0} == 1 || $EUID == 0 ]]; then
    "$@"
  elif [[ -t 0 && -t 1 ]]; then
    sudo "$@"
  else
    pkexec "$@"
  fi
}

install_user_file() {
  local source=$1
  local destination=$2
  local mode=${3:-0644}
  local source_hash destination_hash

  source_hash=$(sha256_file "$source")
  if [[ -f $destination ]]; then
    destination_hash=$(sha256_file "$destination")
    if [[ $destination_hash == "$source_hash" ]]; then
      say "Reusing identical file: $destination"
      return 0
    fi
    if ! manifest_has_path "$OMAZEN_PROFILE_MANIFEST" "$destination" && \
       ! manifest_has_path "$OMAZEN_HOOK_MANIFEST" "$destination"; then
      die "refusing to overwrite unowned file: $destination"
    fi
    backup_owned_file "$destination"
  fi

  mkdir -p -- "$(dirname -- "$destination")"
  install -m "$mode" -- "$source" "$destination"
  if [[ $destination == "$OMAZEN_HOOKS_DIR/"* ]]; then
    record_owned_file "$OMAZEN_HOOK_MANIFEST" "$destination" "$source_hash"
  else
    record_owned_file "$OMAZEN_PROFILE_MANIFEST" "$destination" "$source_hash"
  fi
}

install_program_file() {
  local source=$1
  local destination=$2
  local mode=${3:-0644}
  local source_hash destination_hash

  source_hash=$(sha256_file "$source")
  if [[ -f $destination ]]; then
    destination_hash=$(sha256_file "$destination")
    if [[ $destination_hash == "$source_hash" ]]; then
      say "Reusing identical program file: $destination"
      return 0
    fi
    if ! manifest_has_path "$OMAZEN_PROGRAM_MANIFEST" "$destination"; then
      die "refusing to overwrite unowned program file: $destination"
    fi
    backup_owned_file "$destination"
  fi

  run_privileged mkdir -p -- "$(dirname -- "$destination")"
  run_privileged install -m "$mode" -- "$source" "$destination"
  record_owned_file "$OMAZEN_PROGRAM_MANIFEST" "$destination" "$source_hash"
}

remove_owned_user_file() {
  local manifest=$1
  local path=$2
  local expected current

  expected=$(manifest_hash_for "$manifest" "$path" 2>/dev/null || true)
  [[ -n $expected ]] || return 0
  if [[ -e $path ]]; then
    current=$(sha256_file "$path")
    if [[ $current != "$expected" ]]; then
      warn "leaving modified owned file in place: $path"
      return 1
    fi
    rm -f -- "$path"
    say "Removed: $path"
  fi
  forget_owned_file "$manifest" "$path"
}

remove_owned_program_file() {
  local path=$1
  local expected current

  expected=$(manifest_hash_for "$OMAZEN_PROGRAM_MANIFEST" "$path" 2>/dev/null || true)
  [[ -n $expected ]] || return 0
  if [[ -e $path ]]; then
    current=$(sha256_file "$path")
    if [[ $current != "$expected" ]]; then
      warn "leaving modified program file in place: $path"
      return 1
    fi
    run_privileged rm -f -- "$path"
    say "Removed: $path"
  fi
  forget_owned_file "$OMAZEN_PROGRAM_MANIFEST" "$path"
}

remove_installed_application_copy() {
  local root_canonical data_canonical entry link_target
  [[ -f $OMAZEN_ROOT/.omazen-installed ]] || return 0
  root_canonical=$(realpath -m -- "$OMAZEN_ROOT")
  data_canonical=$(realpath -m -- "$OMAZEN_DATA_DIR")
  [[ $root_canonical == "$data_canonical" ]] || {
    warn "installed marker exists outside configured Omazen data directory; leaving application copy"
    return 1
  }
  [[ $root_canonical != / && $root_canonical != "$OMAZEN_HOME_DIR" ]] || die "unsafe application removal target"

  entry="$OMAZEN_LOCAL_BIN_DIR/omazen"
  if [[ -L $entry ]]; then
    link_target=$(readlink -f -- "$entry")
    if [[ $link_target == "$root_canonical/bin/omazen" ]]; then
      rm -f -- "$entry"
      say "Removed: $entry"
    fi
  fi

  find "$root_canonical" -depth -type f -delete
  find "$root_canonical" -depth -type l -delete
  find "$root_canonical" -depth -type d -empty -delete
  say "Removed installed Omazen application copy: $root_canonical"
}
