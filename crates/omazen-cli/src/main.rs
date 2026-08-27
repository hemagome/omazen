// SPDX-License-Identifier: GPL-3.0-only
// See NOTICE for the required Omazen project attribution terms.

use std::collections::HashMap;
use std::env;
use std::ffi::{OsStr, OsString};
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufRead, BufReader, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{self, Command};
use std::time::{SystemTime, UNIX_EPOCH};

const VERSION: &str = include_str!("../../../VERSION");

#[derive(Debug)]
struct RuntimePaths {
    home_dir: PathBuf,
    state_dir: PathBuf,
    palette_file: PathBuf,
    disabled_file: PathBuf,
    bridge_log: PathBuf,
    bridge_log_archive: PathBuf,
    active_colors: PathBuf,
    skip_theme_hook: bool,
    zen_config_dir: PathBuf,
    zen_program_dir: PathBuf,
    os_release_file: PathBuf,
    hooks_dir: PathBuf,
    omarchy_state_dir: PathBuf,
    project_root: PathBuf,
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
        if !message.is_empty() {
            eprintln!("ERROR: {message}");
        }
        process::exit(1);
    }
}

fn run() -> Result<(), String> {
    validate_embedded_version()?;
    let mut arguments = env::args_os();
    let _program = arguments.next();
    let command = arguments.next().unwrap_or_else(|| OsString::from("help"));
    let trailing: Vec<OsString> = arguments.collect();

    match command.to_str() {
        Some("sync") => {
            require_no_arguments("sync", &trailing)?;
            sync_palette()
        }
        Some("status") => {
            require_no_arguments("status", &trailing)?;
            status()
        }
        Some("doctor") => {
            let json = match trailing.as_slice() {
                [] => false,
                [argument] if argument == OsStr::new("--json") => true,
                _ => return Err("doctor accepts no arguments or --json".to_owned()),
            };
            doctor(json)
        }
        Some("disable") => {
            require_no_arguments("disable", &trailing)?;
            disable()
        }
        Some("enable") => {
            require_no_arguments("enable", &trailing)?;
            enable()
        }
        Some("set") => set_theme(&trailing),
        Some("help" | "-h" | "--help") => {
            print_usage(false);
            Ok(())
        }
        _ => {
            print_usage(true);
            Err(format!("unknown command: {}", command.to_string_lossy()))
        }
    }
}

fn require_no_arguments(command: &str, trailing: &[OsString]) -> Result<(), String> {
    if trailing.is_empty() {
        Ok(())
    } else {
        Err(format!("{command} takes no arguments"))
    }
}

fn print_usage(stderr: bool) {
    const USAGE: &str = concat!(
        "Usage: omazen <command> [arguments]\n",
        "\n",
        "Commands:\n",
        "  setup             Install or repair the Zen integration\n",
        "  sync              Regenerate the normalized palette from active colors.toml\n",
        "  set [theme]       Set an Omarchy theme, or sync the current theme\n",
        "  status            Show concise installation and runtime state\n",
        "  doctor [--json]   Run compatibility and installation diagnostics\n",
        "  disable           Disable Omazen live without removing it\n",
        "  enable            Re-enable Omazen live\n",
        "  uninstall         Remove only files owned by Omazen\n",
        "  help              Show this help\n"
    );
    if stderr {
        eprint!("{USAGE}");
    } else {
        print!("{USAGE}");
    }
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
    let zen_config_dir = nonempty_env("OMAZEN_ZEN_CONFIG_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(&home_dir).join(".config/zen"));
    let zen_program_dir = nonempty_env("OMAZEN_ZEN_PROGRAM_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/opt/zen-browser-bin"));
    let os_release_file = nonempty_env("OMAZEN_OS_RELEASE_FILE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/etc/os-release"));
    let hooks_dir = nonempty_env("OMAZEN_HOOKS_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(&home_dir).join(".config/omarchy/hooks"));
    let project_root = nonempty_env("OMAZEN_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../.."));
    Ok(RuntimePaths {
        home_dir: PathBuf::from(home_dir),
        palette_file: state_dir.join("palette.json"),
        disabled_file: state_dir.join("disabled"),
        bridge_log: state_dir.join("bridge.log"),
        bridge_log_archive: state_dir.join("bridge.log.1"),
        state_dir,
        active_colors,
        skip_theme_hook: provider_mode == OsStr::new("1"),
        zen_config_dir,
        zen_program_dir,
        os_release_file,
        hooks_dir,
        omarchy_state_dir: xdg_state.join("omarchy"),
        project_root,
    })
}

fn status() -> Result<(), String> {
    let paths = runtime_paths()?;
    let platform = platform_summary(&paths.os_release_file);
    let zen_version =
        detect_zen_version(&paths.zen_program_dir).unwrap_or_else(|| "not detected".to_owned());
    let palette_state = if validate_palette_file(&paths.palette_file) {
        format!("valid ({})", paths.palette_file.display())
    } else if paths.palette_file.is_file() {
        format!("invalid ({})", paths.palette_file.display())
    } else {
        "missing".to_owned()
    };
    let enabled_state = if paths.disabled_file.exists() {
        "disabled"
    } else {
        "enabled"
    };
    let profile_count = zen_profiles(&paths).len();
    let provider = if paths.skip_theme_hook {
        "external"
    } else {
        "omarchy-hook"
    };

    println!("Omazen: {}", VERSION.trim_end());
    println!("OS: {platform}");
    println!("State: {enabled_state}");
    println!("Palette provider: {provider}");
    println!("Palette source: {}", paths.active_colors.display());
    println!("Zen: {zen_version}");
    println!("Profiles detected: {profile_count}");
    println!("Palette: {palette_state}");
    if let Some(line) = last_line(&paths.bridge_log) {
        println!("Bridge: {line}");
    } else {
        println!("Bridge: no runtime log yet");
    }
    Ok(())
}

#[derive(Debug)]
struct DoctorCheck {
    status: &'static str,
    message: String,
}

#[derive(Debug, Default)]
struct DoctorReport {
    checks: Vec<DoctorCheck>,
    failures: usize,
    warnings: usize,
    json: bool,
}

impl DoctorReport {
    fn record(&mut self, status: &'static str, message: String) {
        if status == "FAIL" {
            self.failures += 1;
        } else if status == "WARN" {
            self.warnings += 1;
        }
        if !self.json {
            use std::io::IsTerminal;
            let color = std::io::stdout().is_terminal()
                && env::var_os("TERM").is_some_and(|value| value != "dumb")
                && env::var_os("NO_COLOR").is_none();
            if color {
                let code = match status {
                    "PASS" => 32,
                    "WARN" => 33,
                    _ => 31,
                };
                println!("\x1b[{code}m[{status}]\x1b[0m {message}");
            } else {
                println!("[{status}] {message}");
            }
        }
        self.checks.push(DoctorCheck { status, message });
    }

    fn pass(&mut self, message: impl Into<String>) {
        self.record("PASS", message.into());
    }

    fn warn(&mut self, message: impl Into<String>) {
        self.record("WARN", message.into());
    }

    fn fail(&mut self, message: impl Into<String>) {
        self.record("FAIL", message.into());
    }
}

fn doctor(json: bool) -> Result<(), String> {
    let paths = runtime_paths()?;
    let mut report = DoctorReport {
        json,
        ..DoctorReport::default()
    };
    let platform = platform_summary(&paths.os_release_file);
    if platform_supported(&paths.os_release_file) {
        report.pass(format!("supported platform: {platform}"));
    } else {
        report.fail(format!(
            "unsupported platform: {platform}; supported platform is Omarchy Quattro (4.x)"
        ));
    }

    if paths.zen_program_dir.is_dir() && paths.zen_program_dir.join("application.ini").is_file() {
        report.pass(format!(
            "native Zen installation: {}",
            paths.zen_program_dir.display()
        ));
    } else {
        report.fail("supported native Zen installation not found");
    }
    let zen_version = detect_zen_version(&paths.zen_program_dir);
    match zen_version.as_deref() {
        Some("1.21.15b") => report.pass("Zen 1.21.15b (fully validated version)"),
        Some(version) if version_at_least(version, "1.20") => report.warn(format!(
            "Zen {version} is a compatible candidate but has not been fully validated by this release"
        )),
        Some(version) => report.fail(format!(
            "Zen {version} is below the minimum candidate version 1.20"
        )),
        None => report.fail("Zen version could not be detected"),
    }

    if program_has_compatible_fx(&paths.zen_program_dir) {
        report.pass("fx-autoconfig program loader");
    } else {
        report.fail("fx-autoconfig program loader missing or conflicting");
    }
    doctor_exact_file(
        &mut report,
        "required experimental WindowActor preference",
        &paths.zen_program_dir.join("defaults/pref/omazen-prefs.js"),
        &paths.project_root.join("zen/omazen-prefs.js"),
        false,
    );

    let profiles = zen_profiles(&paths);
    for profile in &profiles {
        doctor_profile(&mut report, &paths, profile);
    }
    if profiles.is_empty() {
        report.fail("no Zen profiles detected");
    }

    let provider = if paths.skip_theme_hook {
        report.pass("external palette provider mode (Omarchy hook not required)");
        "external"
    } else {
        doctor_exact_file(
            &mut report,
            "Omarchy theme-set hook",
            &paths.hooks_dir.join("theme-set.d/theme-set"),
            &paths.project_root.join("hooks/theme-set"),
            true,
        );
        report.pass(format!(
            "active Omarchy theme: {}",
            read_private_state_line(&paths.omarchy_state_dir.join("current/theme.name"))
                .map(|value| value.to_string_lossy().into_owned())
                .unwrap_or_else(|| "unknown".to_owned())
        ));
        "omarchy-hook"
    };
    report.pass(format!(
        "active palette source: {}",
        paths.active_colors.display()
    ));

    let palette_result = palette_diagnosis(&paths);
    let palette_valid = palette_result.is_ok();
    if let Err(reason) = &palette_result {
        report.fail(format!(
            "normalized palette is missing, invalid, or stale: {} ({reason})",
            paths.palette_file.display()
        ));
    } else {
        report.pass("normalized palette is valid, canonical, and current");
    }
    let disabled = paths.disabled_file.exists();
    if disabled {
        report.warn("Omazen is disabled");
    } else {
        report.pass("Omazen is enabled");
    }

    let logs: Vec<PathBuf> = [&paths.bridge_log_archive, &paths.bridge_log]
        .into_iter()
        .filter(|path| path.is_file())
        .cloned()
        .collect();
    let log_lines = read_log_lines(&logs);
    let bridge_version =
        latest_field_line(&log_lines, "BRIDGE_LOADED version=", "version=").unwrap_or_default();
    let bridge_timestamp = log_lines
        .iter()
        .filter(|line| timestamp_prefix(line).is_some())
        .filter_map(|line| timestamp_prefix(line).map(str::to_owned))
        .next_back()
        .unwrap_or_default();
    let bridge_age = timestamp_age_seconds(&bridge_timestamp);
    if bridge_version == VERSION.trim_end() {
        report.pass(format!("bridge {bridge_version} has loaded in Zen"));
    } else if bridge_version.is_empty() {
        report.warn("bridge has not logged a successful load yet; initial normal restart may still be pending");
    } else {
        report.fail(format!(
            "loaded bridge version {bridge_version} does not match Omazen {}",
            VERSION.trim_end()
        ));
    }

    if disabled {
        report.pass("bridge palette application checks skipped while Omazen is disabled");
    } else if palette_valid {
        let palette_text = fs::read_to_string(&paths.palette_file).unwrap_or_default();
        let accent = palette_json_value(&palette_text, "accent").unwrap_or_default();
        let mode = palette_json_value(&palette_text, "mode").unwrap_or_default();
        match latest_event(&log_lines, "PALETTE_APPLIED") {
            Some(event)
                if event.get("accent").map(String::as_str) == Some(accent.as_str())
                    && event.get("mode").map(String::as_str) == Some(mode.as_str()) =>
            {
                report.pass(format!(
                    "bridge applied current palette accent={accent} mode={mode} profile={}",
                    event.get("profile").map(String::as_str).unwrap_or("legacy")
                ));
            }
            Some(event) => report.fail(format!(
                "bridge palette is stale: applied accent={} mode={}; current accent={accent} mode={mode}",
                event.get("accent").map(String::as_str).unwrap_or(""),
                event.get("mode").map(String::as_str).unwrap_or("")
            )),
            None => report.warn("bridge has not logged a palette application for the current palette yet"),
        }
        match latest_event(&log_lines, "CHROME_CSS_APPLIED") {
            Some(event) if event.get("primary").map(String::as_str) == Some(accent.as_str()) => {
                report.pass(format!(
                    "bridge CSS exposes current primary color {accent} profile={}",
                    event.get("profile").map(String::as_str).unwrap_or("legacy")
                ));
            }
            Some(event) => report.fail(format!(
                "bridge CSS is stale: applied primary={}; current accent={accent}",
                event.get("primary").map(String::as_str).unwrap_or("")
            )),
            None => report
                .warn("bridge has not logged a successful CSS probe for the current palette yet"),
        }
    } else {
        report.warn(
            "bridge palette application checks skipped because the normalized palette is invalid",
        );
    }

    if let Some(error) = current_bridge_error(&log_lines) {
        report.fail(format!("current bridge error: {error}"));
    } else {
        report.pass("no current bridge error recorded");
    }
    if bridge_timestamp.is_empty() {
        report.warn("bridge log has no runtime events yet");
    } else if let Some(age) = bridge_age {
        report.pass(format!(
            "bridge log last event: {bridge_timestamp} (age {age}s)"
        ));
    } else {
        report.pass(format!("bridge log last event: {bridge_timestamp}"));
    }
    if paths.home_dir.join(".var/app/app.zen_browser.zen").is_dir()
        || paths
            .home_dir
            .join(".var/app/io.github.zen_browser.zen")
            .is_dir()
    {
        report.warn("Flatpak Zen detected; Flatpak is outside this MVP because the sandbox blocks this backend");
    }

    if json {
        emit_doctor_json(
            &report,
            &paths,
            &platform,
            zen_version.as_deref().unwrap_or("unknown"),
            provider,
            &profiles,
            &bridge_version,
            &bridge_timestamp,
            bridge_age,
            &logs,
        );
    } else {
        println!(
            "\nDoctor: {} failure(s), {} warning(s)",
            report.failures, report.warnings
        );
    }
    if report.failures == 0 {
        Ok(())
    } else {
        Err(String::new())
    }
}

fn platform_supported(path: &Path) -> bool {
    os_release_value(path, "ID").as_deref() == Some("omarchy")
        && os_release_value(path, "VERSION_ID")
            .or_else(|| os_release_value(path, "BUILD_ID"))
            .and_then(|version| version.split('.').next().map(str::to_owned))
            .as_deref()
            == Some("4")
}

fn version_at_least(have: &str, wanted: &str) -> bool {
    fn parts(version: &str) -> Vec<u64> {
        version
            .trim_start_matches('v')
            .split(|character: char| !character.is_ascii_digit() && character != '.')
            .next()
            .unwrap_or("")
            .split('.')
            .map(|part| part.parse().unwrap_or(0))
            .collect()
    }
    parts(have) >= parts(wanted)
}

fn file_contains(path: &Path, needle: &str) -> bool {
    fs::read(path).ok().is_some_and(|bytes| {
        bytes
            .windows(needle.len())
            .any(|window| window == needle.as_bytes())
    })
}

fn directory_contains(directory: &Path, needle: &str) -> bool {
    let Ok(entries) = fs::read_dir(directory) else {
        return false;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() && directory_contains(&path, needle) {
            return true;
        }
        if path.is_file() && file_contains(&path, needle) {
            return true;
        }
    }
    false
}

fn program_has_compatible_fx(program_dir: &Path) -> bool {
    file_contains(
        &program_dir.join("config.js"),
        "chrome://userchromejs/content/boot.sys.mjs",
    ) && directory_contains(
        &program_dir.join("defaults/pref"),
        "general.config.filename\", \"config.js\"",
    )
}

fn doctor_exact_file(
    report: &mut DoctorReport,
    label: &str,
    installed: &Path,
    expected: &Path,
    executable: bool,
) {
    let Ok(metadata) = fs::symlink_metadata(installed) else {
        report.fail(format!("{label} is missing: {}", installed.display()));
        return;
    };
    if metadata.file_type().is_symlink() {
        report.fail(format!(
            "{label} is a symbolic link: {}",
            installed.display()
        ));
        return;
    }
    if !metadata.is_file() {
        report.fail(format!("{label} is missing: {}", installed.display()));
        return;
    }
    if fs::read(installed).ok() != fs::read(expected).ok() {
        report.fail(format!(
            "{label} is modified or outdated: {}",
            installed.display()
        ));
        return;
    }
    let mode = metadata.permissions().mode();
    if mode & 0o022 != 0 {
        report.fail(format!(
            "{label} has unsafe group/world write permissions: {}",
            installed.display()
        ));
        return;
    }
    if executable && mode & 0o111 == 0 {
        report.fail(format!(
            "{label} is not executable: {}",
            installed.display()
        ));
        return;
    }
    report.pass(format!("{label} integrity: {}", installed.display()));
}

fn doctor_profile(report: &mut DoctorReport, paths: &RuntimePaths, profile: &Path) {
    const FX_FILES: &[&str] = &[
        "boot.sys.mjs",
        "chrome.manifest",
        "fs.sys.mjs",
        "module_loader.mjs",
        "uc_api.sys.mjs",
        "utils.sys.mjs",
    ];
    let compatible = FX_FILES
        .iter()
        .all(|name| profile.join("chrome/utils").join(name).is_file())
        && file_contains(
            &profile.join("chrome/utils/boot.sys.mjs"),
            "buildScriptActorDefinition",
        )
        && file_contains(
            &profile.join("chrome/utils/chrome.manifest"),
            "content userscripts",
        );
    if compatible {
        report.pass(format!(
            "fx-autoconfig profile runtime: {}",
            profile.display()
        ));
    } else {
        report.fail(format!(
            "fx-autoconfig profile runtime missing or incompatible: {}",
            profile.display()
        ));
    }
    for relative in [
        "omazen-bridge.uc.js",
        "Omazen/OmazenParent.sys.mjs",
        "Omazen/OmazenChild.sys.mjs",
        "Omazen/OmazenPalette.sys.mjs",
        "Omazen/OmazenWatcher.sys.mjs",
    ] {
        doctor_exact_file(
            report,
            &format!("profile file {relative}"),
            &profile.join("chrome/JS").join(relative),
            &paths.project_root.join("zen").join(relative),
            false,
        );
    }
}

fn palette_json_value(text: &str, key: &str) -> Option<String> {
    let prefix = format!("  \"{key}\": \"");
    text.lines()
        .find_map(|line| line.strip_prefix(&prefix))
        .and_then(|value| value.split('"').next())
        .map(str::to_owned)
}

fn palette_diagnosis(paths: &RuntimePaths) -> Result<(), String> {
    if fs::symlink_metadata(&paths.palette_file)
        .ok()
        .is_some_and(|metadata| metadata.file_type().is_symlink())
    {
        return Err(format!(
            "palette file is a symbolic link: {}",
            paths.palette_file.display()
        ));
    }
    if !paths.palette_file.is_file() {
        return Err(format!(
            "palette file is missing: {}",
            paths.palette_file.display()
        ));
    }
    if !validate_palette_file(&paths.palette_file) {
        return Err(format!(
            "palette JSON is invalid or non-canonical: {}",
            paths.palette_file.display()
        ));
    }
    let expected = parse_colors_file(&paths.active_colors).map_err(|_| {
        format!(
            "active colors file is missing or invalid: {}",
            paths.active_colors.display()
        )
    })?;
    let text = fs::read_to_string(&paths.palette_file).unwrap_or_default();
    for (key, wanted) in [
        ("mode", expected.mode.as_str()),
        ("accent", expected.accent.as_str()),
        ("background", expected.background.as_str()),
        ("background_dark", expected.background_dark.as_str()),
        ("background_light", expected.background_light.as_str()),
        ("foreground", expected.foreground.as_str()),
        ("foreground_muted", expected.foreground_muted.as_str()),
        ("selection", expected.selection.as_str()),
        ("border", expected.border.as_str()),
    ] {
        let actual = palette_json_value(&text, key).unwrap_or_default();
        if actual != wanted {
            return Err(format!("{key} mismatch: palette={actual}, active={wanted}"));
        }
    }
    Ok(())
}

fn read_log_lines(paths: &[PathBuf]) -> Vec<String> {
    paths
        .iter()
        .filter_map(|path| fs::read_to_string(path).ok())
        .flat_map(|text| text.lines().map(str::to_owned).collect::<Vec<_>>())
        .collect()
}

fn timestamp_prefix(line: &str) -> Option<&str> {
    let value = line.split_whitespace().next()?;
    (value.len() >= 20 && value.as_bytes().get(4) == Some(&b'-')).then_some(value)
}

fn latest_field_line(lines: &[String], marker: &str, field: &str) -> Option<String> {
    lines
        .iter()
        .filter(|line| line.contains(marker))
        .filter_map(|line| {
            line.split_whitespace()
                .find_map(|item| item.strip_prefix(field).map(str::to_owned))
        })
        .next_back()
}

fn latest_event(lines: &[String], marker: &str) -> Option<HashMap<String, String>> {
    lines
        .iter()
        .filter(|line| line.contains(&format!("[INFO] {marker} ")))
        .map(|line| {
            line.split_whitespace()
                .filter_map(|item| item.split_once('='))
                .map(|(key, value)| (key.to_owned(), value.to_owned()))
                .collect()
        })
        .next_back()
}

fn current_bridge_error(lines: &[String]) -> Option<String> {
    let mut error = None;
    for line in lines {
        if line.contains("[ERROR]") {
            error = Some(line.clone());
        } else if [
            "BRIDGE_LOADED",
            "PALETTE_APPLIED",
            "CHROME_CSS_APPLIED",
            "DISABLED",
        ]
        .iter()
        .any(|event| line.contains(&format!("[INFO] {event}")))
        {
            error = None;
        }
    }
    error
}

fn timestamp_age_seconds(timestamp: &str) -> Option<u64> {
    if timestamp.len() < 19 {
        return None;
    }
    let year = timestamp.get(0..4)?.parse::<i64>().ok()?;
    let month = timestamp.get(5..7)?.parse::<i64>().ok()?;
    let day = timestamp.get(8..10)?.parse::<i64>().ok()?;
    let hour = timestamp.get(11..13)?.parse::<i64>().ok()?;
    let minute = timestamp.get(14..16)?.parse::<i64>().ok()?;
    let second = timestamp.get(17..19)?.parse::<i64>().ok()?;
    let year_adjusted = year - i64::from(month <= 2);
    let era = year_adjusted.div_euclid(400);
    let year_of_era = year_adjusted - era * 400;
    let month_prime = month + if month > 2 { -3 } else { 9 };
    let day_of_year = (153 * month_prime + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    let days = era * 146097 + day_of_era - 719468;
    let event = days * 86400 + hour * 3600 + minute * 60 + second;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs() as i64;
    Some(now.saturating_sub(event) as u64)
}

fn json_escape(value: &str) -> String {
    let mut escaped = String::new();
    for character in value.chars() {
        match character {
            '\\' => escaped.push_str("\\\\"),
            '"' => escaped.push_str("\\\""),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            _ => escaped.push(character),
        }
    }
    escaped
}

#[allow(clippy::too_many_arguments)]
fn emit_doctor_json(
    report: &DoctorReport,
    paths: &RuntimePaths,
    platform: &str,
    zen_version: &str,
    provider: &str,
    profiles: &[PathBuf],
    bridge_version: &str,
    bridge_timestamp: &str,
    bridge_age: Option<u64>,
    logs: &[PathBuf],
) {
    println!("{{");
    println!("  \"schema_version\": 1,");
    println!("  \"ok\": {},", report.failures == 0);
    println!("  \"omazen_version\": \"{}\",", VERSION.trim_end());
    println!("  \"platform\": \"{}\",", json_escape(platform));
    println!("  \"zen_version\": \"{}\",", json_escape(zen_version));
    println!("  \"provider\": \"{provider}\",");
    let theme = read_private_state_line(&paths.omarchy_state_dir.join("current/theme.name"))
        .map(|value| value.to_string_lossy().into_owned())
        .unwrap_or_else(|| "unknown".to_owned());
    println!("  \"theme\": \"{}\",", json_escape(&theme));
    println!(
        "  \"active_colors\": \"{}\",",
        json_escape(&paths.active_colors.to_string_lossy())
    );
    println!(
        "  \"palette_file\": \"{}\",",
        json_escape(&paths.palette_file.to_string_lossy())
    );
    println!("  \"profiles_detected\": {},", profiles.len());
    println!("  \"bridge_version\": \"{}\",", json_escape(bridge_version));
    println!(
        "  \"bridge_last_event\": \"{}\",",
        json_escape(bridge_timestamp)
    );
    match bridge_age {
        Some(age) => println!("  \"bridge_last_event_age_seconds\": {age},"),
        None => println!("  \"bridge_last_event_age_seconds\": null,"),
    }
    print!("  \"bridge_logs\": [");
    for (index, path) in logs.iter().enumerate() {
        if index > 0 {
            print!(", ");
        }
        print!("\"{}\"", json_escape(&path.to_string_lossy()));
    }
    println!("],");
    println!("  \"failures\": {},", report.failures);
    println!("  \"warnings\": {},", report.warnings);
    println!("  \"generated_at\": \"{}\",", utc_timestamp());
    print!("  \"checks\": [");
    for (index, check) in report.checks.iter().enumerate() {
        if index > 0 {
            print!(", ");
        }
        print!(
            "{{\"status\":\"{}\",\"message\":\"{}\"}}",
            check.status,
            json_escape(&check.message)
        );
    }
    println!("]");
    println!("}}");
}

fn utc_timestamp() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    let days = seconds.div_euclid(86400);
    let day_seconds = seconds.rem_euclid(86400);
    let adjusted = days + 719468;
    let era = adjusted.div_euclid(146097);
    let day_of_era = adjusted - era * 146097;
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;
    let mut year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_prime = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_prime + 2) / 5 + 1;
    let month = month_prime + if month_prime < 10 { 3 } else { -9 };
    year += i64::from(month <= 2);
    let hour = day_seconds / 3600;
    let minute = day_seconds % 3600 / 60;
    let second = day_seconds % 60;
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z")
}

fn os_release_value(path: &Path, wanted: &str) -> Option<String> {
    let text = fs::read_to_string(path).ok()?;
    for line in text.lines() {
        let Some((key, raw)) = line.split_once('=') else {
            continue;
        };
        if key != wanted {
            continue;
        }
        return Some(
            raw.strip_prefix('"')
                .and_then(|value| value.strip_suffix('"'))
                .or_else(|| {
                    raw.strip_prefix('\'')
                        .and_then(|value| value.strip_suffix('\''))
                })
                .unwrap_or(raw)
                .to_owned(),
        );
    }
    None
}

fn platform_summary(path: &Path) -> String {
    let id = os_release_value(path, "ID").unwrap_or_else(|| "unknown".to_owned());
    let mut name = os_release_value(path, "PRETTY_NAME")
        .or_else(|| os_release_value(path, "NAME"))
        .unwrap_or_else(|| "unknown".to_owned());
    let version = os_release_value(path, "VERSION_ID")
        .or_else(|| os_release_value(path, "BUILD_ID"))
        .unwrap_or_else(|| "unknown".to_owned());
    if version != "unknown" && !name.contains(&version) {
        name.push(' ');
        name.push_str(&version);
    }
    format!("{name} ({id})")
}

fn detect_zen_version(program_dir: &Path) -> Option<String> {
    if let Some(version) = env::var_os("OMAZEN_ZEN_VERSION_OVERRIDE") {
        return Some(version.to_string_lossy().into_owned());
    }
    if let Ok(text) = fs::read_to_string(program_dir.join("application.ini")) {
        for line in text.lines() {
            if let Some(version) = line.strip_prefix("Version=") {
                return Some(version.to_owned());
            }
        }
    }
    let output = Command::new("zen-browser").arg("--version").output().ok()?;
    if !output.status.success() {
        return None;
    }
    String::from_utf8(output.stdout)
        .ok()?
        .split_whitespace()
        .last()
        .map(str::to_owned)
}

fn zen_profiles(paths: &RuntimePaths) -> Vec<PathBuf> {
    if let Some(profile) = nonempty_env("OMAZEN_PROFILE") {
        let profile = PathBuf::from(profile);
        return profile
            .is_dir()
            .then(|| fs::canonicalize(&profile).unwrap_or(profile))
            .into_iter()
            .collect();
    }
    let Ok(text) = fs::read_to_string(paths.zen_config_dir.join("profiles.ini")) else {
        return Vec::new();
    };
    let config_canonical =
        fs::canonicalize(&paths.zen_config_dir).unwrap_or_else(|_| paths.zen_config_dir.clone());
    let mut profiles = Vec::new();
    let mut section = String::new();
    let mut relative = false;
    let mut profile_path: Option<String> = None;
    let mut emit = |section: &str, relative: bool, profile_path: &mut Option<String>| {
        let Some(raw) = profile_path.take() else {
            return;
        };
        if !section.starts_with("[Profile") || !section.ends_with(']') {
            return;
        }
        let candidate = if relative {
            paths.zen_config_dir.join(raw)
        } else {
            PathBuf::from(raw)
        };
        if !candidate.is_dir() {
            return;
        }
        let canonical = fs::canonicalize(&candidate).unwrap_or(candidate);
        if relative && !canonical.starts_with(&config_canonical) {
            return;
        }
        profiles.push(canonical);
    };
    for line in text.lines() {
        if line.starts_with('[') {
            emit(&section, relative, &mut profile_path);
            section = line.to_owned();
            relative = false;
        } else if let Some(value) = line.strip_prefix("Path=") {
            profile_path = Some(value.to_owned());
        } else if line == "IsRelative=1" {
            relative = true;
        }
    }
    emit(&section, relative, &mut profile_path);
    profiles
}

fn last_line(path: &Path) -> Option<String> {
    let text = fs::read_to_string(path).ok()?;
    text.lines().last().map(str::to_owned)
}

fn validate_palette_file(path: &Path) -> bool {
    let Ok(bytes) = fs::read(path) else {
        return false;
    };
    if bytes.len() > 2048 || !bytes.ends_with(b"\n") {
        return false;
    }
    let Ok(text) = String::from_utf8(bytes) else {
        return false;
    };
    let lines: Vec<&str> = text.lines().collect();
    if lines.len() != 12 || lines.first() != Some(&"{") || lines.last() != Some(&"}") {
        return false;
    }
    if !lines.contains(&"  \"schema_version\": 1,") {
        return false;
    }
    if !lines
        .iter()
        .any(|line| *line == "  \"mode\": \"dark\"," || *line == "  \"mode\": \"light\",")
    {
        return false;
    }
    let color_line = |key: &str, comma: bool| {
        let prefix = format!("  \"{key}\": \"#");
        lines.iter().any(|line| {
            line.starts_with(&prefix)
                && line.len() == prefix.len() + 6 + 1 + usize::from(comma)
                && line[prefix.len()..prefix.len() + 6]
                    .bytes()
                    .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
                && line.ends_with(if comma { "\"," } else { "\"" })
        })
    };
    for key in [
        "accent",
        "background",
        "background_dark",
        "background_light",
        "foreground",
        "foreground_muted",
        "selection",
    ] {
        if !color_line(key, true) {
            return false;
        }
    }
    color_line("border", false)
        && lines
            .iter()
            .filter(|line| line.starts_with("  \"") && line.contains("\":"))
            .count()
            == 10
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

fn disable() -> Result<(), String> {
    let paths = runtime_paths()?;
    ensure_state_dirs(&paths.state_dir).map_err(|error| error.to_string())?;
    let file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&paths.disabled_file)
        .map_err(|error| error.to_string())?;
    file.set_permissions(fs::Permissions::from_mode(0o600))
        .map_err(|error| error.to_string())?;
    println!("Omazen disabled. Open Zen windows will revert automatically.");
    Ok(())
}

fn enable() -> Result<(), String> {
    let paths = runtime_paths()?;
    sync_palette()?;
    match fs::remove_file(&paths.disabled_file) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.to_string()),
    }
    println!("Omazen enabled. Open Zen windows will update automatically.");
    Ok(())
}

fn set_theme(arguments: &[OsString]) -> Result<(), String> {
    if arguments.len() > 1 {
        return Err("set accepts zero arguments or one quoted theme name".to_owned());
    }
    if let Some(theme) = arguments.first() {
        let status = Command::new("omarchy")
            .args([OsStr::new("theme"), OsStr::new("set"), theme.as_os_str()])
            .status();
        match status {
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                return Err("required command not found: omarchy".to_owned());
            }
            Err(error) => return Err(error.to_string()),
            Ok(status) if !status.success() => return Err(String::new()),
            Ok(_) => {}
        }
    }
    sync_palette()
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
