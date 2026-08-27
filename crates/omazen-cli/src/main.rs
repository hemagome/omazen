// SPDX-License-Identifier: GPL-3.0-only
// See NOTICE for the required Omazen project attribution terms.

use std::collections::HashMap;
use std::env;
use std::ffi::{OsStr, OsString};
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufRead, BufReader, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

const VERSION: &str = include_str!("../../../VERSION");

#[derive(Debug)]
struct RuntimePaths {
    state_dir: PathBuf,
    palette_file: PathBuf,
    active_colors: PathBuf,
}

#[derive(Debug, PartialEq, Eq)]
struct Palette {
    mode: String,
    accent: String,
    background: String,
    background_dark: String,
    background_light: String,
    foreground: String,
    foreground_muted: String,
    selection: String,
    border: String,
}

fn main() {
    if let Err(message) = run() {
        eprintln!("ERROR: {message}");
        process::exit(1);
    }
}

fn run() -> Result<(), String> {
    validate_embedded_version()?;
    let mut arguments = env::args_os();
    let _program = arguments.next();
    let command = arguments.next().unwrap_or_else(|| OsString::from("help"));
    let trailing: Vec<OsString> = arguments.collect();

    if command == OsStr::new("sync") {
        if !trailing.is_empty() {
            return Err("sync takes no arguments".to_owned());
        }
        return sync_palette();
    }

    Err(format!(
        "command is not migrated to Rust yet: {}",
        command.to_string_lossy()
    ))
}

fn validate_embedded_version() -> Result<(), String> {
    let version = VERSION.trim_end();
    let parts: Vec<&str> = version.split('.').collect();
    if parts.len() == 3
        && parts
            .iter()
            .all(|part| !part.is_empty() && part.bytes().all(|byte| byte.is_ascii_digit()))
    {
        Ok(())
    } else {
        Err("invalid embedded Omazen version".to_owned())
    }
}

fn nonempty_env(name: &str) -> Option<OsString> {
    env::var_os(name).filter(|value| !value.is_empty())
}

fn read_private_state_line(path: &Path) -> Option<OsString> {
    let metadata = fs::symlink_metadata(path).ok()?;
    if metadata.file_type().is_symlink() || !metadata.file_type().is_file() {
        return None;
    }
    let file = File::open(path).ok()?;
    let mut line = OsString::new();
    let bytes = BufReader::new(file).split(b'\n').next()?.ok()?;
    if bytes.is_empty() {
        return None;
    }
    use std::os::unix::ffi::OsStringExt;
    line.push(OsString::from_vec(bytes));
    Some(line)
}

fn runtime_paths() -> Result<RuntimePaths, String> {
    let home_dir = nonempty_env("OMAZEN_HOME_DIR")
        .or_else(|| nonempty_env("HOME"))
        .ok_or_else(|| "HOME is not set".to_owned())?;
    let xdg_state = nonempty_env("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(&home_dir).join(".local/state"));
    let state_dir = nonempty_env("OMAZEN_STATE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| xdg_state.join("omazen"));
    let provider_mode_file = state_dir.join("provider-mode");
    let provider_mode = env::var_os("OMAZEN_SKIP_THEME_HOOK")
        .or_else(|| read_private_state_line(&provider_mode_file))
        .unwrap_or_else(|| OsString::from("0"));
    if provider_mode != OsStr::new("0") && provider_mode != OsStr::new("1") {
        return Err("OMAZEN_SKIP_THEME_HOOK must be 0 or 1".to_owned());
    }
    let active_colors_file = state_dir.join("active-colors");
    let active_colors = env::var_os("OMAZEN_ACTIVE_COLORS")
        .or_else(|| read_private_state_line(&active_colors_file))
        .map(PathBuf::from)
        .unwrap_or_else(|| xdg_state.join("omarchy/current/theme/colors.toml"));
    Ok(RuntimePaths {
        palette_file: state_dir.join("palette.json"),
        state_dir,
        active_colors,
    })
}

fn sync_palette() -> Result<(), String> {
    let paths = runtime_paths()?;
    let palette = parse_colors_file(&paths.active_colors).map_err(|_| {
        format!(
            "invalid or missing Quattro palette: {}",
            paths.active_colors.display()
        )
    })?;
    ensure_state_dirs(&paths.state_dir).map_err(|error| error.to_string())?;
    write_palette_atomic(&paths.palette_file, &palette).map_err(|error| error.to_string())?;
    println!(
        "Palette synchronized atomically: {}",
        paths.palette_file.display()
    );
    Ok(())
}

fn ensure_state_dirs(state_dir: &Path) -> io::Result<()> {
    for directory in [
        state_dir.to_path_buf(),
        state_dir.join("owned"),
        state_dir.join("backups"),
    ] {
        fs::create_dir_all(&directory)?;
        fs::set_permissions(&directory, fs::Permissions::from_mode(0o700))?;
    }
    Ok(())
}

fn parse_colors_file(path: &Path) -> Result<Palette, ()> {
    let file = File::open(path).map_err(|_| ())?;
    let mut values = HashMap::new();
    for line in BufReader::new(file).split(b'\n') {
        let mut line = line.map_err(|_| ())?;
        if line.last() == Some(&b'\r') {
            line.pop();
        }
        if let Some((key, value)) = parse_assignment(&line) {
            values.insert(key, value);
        }
    }

    let mode = required(&values, "mode")?;
    if mode != "dark" && mode != "light" {
        return Err(());
    }
    for key in [
        "accent",
        "selection",
        "muted",
        "background",
        "dark_background",
        "lighter_background",
        "foreground",
    ] {
        if !is_color(required(&values, key)?) {
            return Err(());
        }
    }
    let muted = required(&values, "muted")?.to_ascii_lowercase();
    let border = values
        .get("active_border_color")
        .filter(|value| is_color(value))
        .map(|value| value.to_ascii_lowercase())
        .unwrap_or_else(|| muted.clone());
    Ok(Palette {
        mode: mode.to_owned(),
        accent: required(&values, "accent")?.to_ascii_lowercase(),
        background: required(&values, "background")?.to_ascii_lowercase(),
        background_dark: required(&values, "dark_background")?.to_ascii_lowercase(),
        background_light: required(&values, "lighter_background")?.to_ascii_lowercase(),
        foreground: required(&values, "foreground")?.to_ascii_lowercase(),
        foreground_muted: muted,
        selection: required(&values, "selection")?.to_ascii_lowercase(),
        border,
    })
}

fn required<'a>(values: &'a HashMap<String, String>, key: &str) -> Result<&'a str, ()> {
    values.get(key).map(String::as_str).ok_or(())
}

fn is_space(byte: u8) -> bool {
    matches!(byte, b' ' | b'\t' | 0x0b | 0x0c | b'\r' | b'\n')
}

fn parse_assignment(line: &[u8]) -> Option<(String, String)> {
    let mut index = 0;
    while index < line.len() && is_space(line[index]) {
        index += 1;
    }
    if index == line.len() || line[index] == b'#' {
        return None;
    }
    let key_start = index;
    while index < line.len() && (line[index].is_ascii_alphanumeric() || line[index] == b'_') {
        index += 1;
    }
    if index == key_start {
        return None;
    }
    let key_end = index;
    while index < line.len() && is_space(line[index]) {
        index += 1;
    }
    if line.get(index) != Some(&b'=') {
        return None;
    }
    index += 1;
    while index < line.len() && is_space(line[index]) {
        index += 1;
    }
    if line.get(index) != Some(&b'"') {
        return None;
    }
    index += 1;
    let value_start = index;
    while index < line.len() && line[index] != b'"' {
        index += 1;
    }
    if index == line.len() {
        return None;
    }
    let value_end = index;
    index += 1;
    while index < line.len() && is_space(line[index]) {
        index += 1;
    }
    if index < line.len() && line[index] != b'#' {
        return None;
    }
    let key = String::from_utf8(line[key_start..key_end].to_vec()).ok()?;
    let value = String::from_utf8(line[value_start..value_end].to_vec()).ok()?;
    Some((key, value))
}

fn is_color(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() == 7 && bytes[0] == b'#' && bytes[1..].iter().all(u8::is_ascii_hexdigit)
}

fn canonical_palette(palette: &Palette) -> String {
    format!(
        concat!(
            "{{\n",
            "  \"schema_version\": 1,\n",
            "  \"mode\": \"{}\",\n",
            "  \"accent\": \"{}\",\n",
            "  \"background\": \"{}\",\n",
            "  \"background_dark\": \"{}\",\n",
            "  \"background_light\": \"{}\",\n",
            "  \"foreground\": \"{}\",\n",
            "  \"foreground_muted\": \"{}\",\n",
            "  \"selection\": \"{}\",\n",
            "  \"border\": \"{}\"\n",
            "}}\n"
        ),
        palette.mode,
        palette.accent,
        palette.background,
        palette.background_dark,
        palette.background_light,
        palette.foreground,
        palette.foreground_muted,
        palette.selection,
        palette.border
    )
}

fn write_palette_atomic(destination: &Path, palette: &Palette) -> io::Result<()> {
    let parent = destination.parent().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            "palette destination has no parent",
        )
    })?;
    let mut attempt = 0_u32;
    let mut temporary_path;
    let mut temporary;
    loop {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        temporary_path = parent.join(format!(
            ".palette.json.{:x}{:x}{:x}",
            process::id(),
            nonce,
            attempt
        ));
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&temporary_path)
        {
            Ok(file) => {
                temporary = file;
                break;
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists && attempt < 100 => {
                attempt += 1;
            }
            Err(error) => return Err(error),
        }
    }
    let result = (|| {
        temporary.write_all(canonical_palette(palette).as_bytes())?;
        temporary.flush()?;
        drop(temporary);
        fs::rename(&temporary_path, destination)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary_path);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::{Palette, canonical_palette, is_color, parse_assignment};

    #[test]
    fn assignment_contract() {
        assert_eq!(
            parse_assignment(b"  accent = \"#AABBCC\" # comment"),
            Some(("accent".to_owned(), "#AABBCC".to_owned()))
        );
        assert_eq!(parse_assignment(b"accent = bare"), None);
        assert_eq!(parse_assignment(b"accent = \"#112233\" trailing"), None);
        assert_eq!(parse_assignment(b"# accent = \"#112233\""), None);
    }

    #[test]
    fn color_contract() {
        assert!(is_color("#Aa01fF"));
        assert!(!is_color("#12345"));
        assert!(!is_color("112233"));
    }

    #[test]
    fn canonical_bytes_are_stable() {
        let palette = Palette {
            mode: "dark".to_owned(),
            accent: "#112233".to_owned(),
            background: "#223344".to_owned(),
            background_dark: "#000000".to_owned(),
            background_light: "#334455".to_owned(),
            foreground: "#eeeeee".to_owned(),
            foreground_muted: "#778899".to_owned(),
            selection: "#445566".to_owned(),
            border: "#778899".to_owned(),
        };
        assert_eq!(canonical_palette(&palette).lines().count(), 12);
        assert!(canonical_palette(&palette).ends_with("}\n"));
    }
}
