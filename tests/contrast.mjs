/* SPDX-License-Identifier: GPL-3.0-only */
/* See NOTICE for the required Omazen project attribution terms. */

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  contrastRatio,
  deriveAccentForeground,
} from "../zen/Omazen/OmazenPalette.sys.mjs";

const PROJECT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const REQUIRED_KEYS = [
  "mode",
  "accent",
  "selection",
  "muted",
  "background",
  "dark_background",
  "lighter_background",
  "foreground",
];
const FALLBACK_FIXTURE_ROOT = path.join(PROJECT_ROOT, "tests", "fixtures", "contrast-palettes");
const STOCK_ROOTS = [
  "/usr/share/omarchy/themes",
  path.join(os.homedir(), ".config", "omarchy", "themes"),
];

function usage() {
  console.log("Usage: node tests/contrast.mjs [--strict] [PALETTE_DIR ...]");
  console.log("       OMAZEN_CONTRAST_PALETTE_DIR may contain a path-list of palette directories.");
}

const argumentsList = process.argv.slice(2);
if (argumentsList.includes("--help")) {
  usage();
  process.exit(0);
}
const strict = argumentsList.includes("--strict") || process.env.OMAZEN_CONTRAST_STRICT === "1";
const explicitRoots = argumentsList.filter(argument => argument !== "--strict");
const configuredRoots = process.env.OMAZEN_CONTRAST_PALETTE_DIR
  ?.split(path.delimiter)
  .filter(Boolean) || [];

function discover(root) {
  const resolvedRoot = path.resolve(root);
  let stat;
  try {
    stat = fs.statSync(resolvedRoot);
  } catch {
    return [];
  }
  if (stat.isFile()) return path.basename(resolvedRoot) === "colors.toml" ? [resolvedRoot] : [];
  if (!stat.isDirectory()) return [];

  const result = [];
  for (const entry of fs.readdirSync(resolvedRoot, { withFileTypes: true })) {
    const candidate = path.join(resolvedRoot, entry.name);
    if (entry.isDirectory()) {
      const colors = path.join(candidate, "colors.toml");
      try {
        if (fs.statSync(colors).isFile()) result.push(colors);
      } catch {
        // A theme can disappear while Omarchy is updating its theme directory.
      }
    } else if (
      entry.isFile()
      && (entry.name === "colors.toml"
        || (resolvedRoot === FALLBACK_FIXTURE_ROOT && entry.name.endsWith(".toml")))
    ) {
      result.push(candidate);
    }
  }
  return result.sort();
}

function parseColors(file) {
  const values = {};
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*"([^"]*)"\s*(?:#.*)?$/);
    if (match) values[match[1]] = match[2].toLowerCase();
  }
  for (const key of REQUIRED_KEYS) {
    if (key === "mode") {
      if (values.mode !== "dark" && values.mode !== "light") {
        throw new Error(`invalid mode: ${values.mode || "missing"}`);
      }
    } else if (!/^#[0-9a-f]{6}$/.test(values[key] || "")) {
      throw new Error(`invalid or missing color: ${key}`);
    }
  }
  return {
    mode: values.mode,
    accent: values.accent,
    selection: values.selection,
    foreground_muted: values.muted,
    background: values.background,
    background_dark: values.dark_background,
    background_light: values.lighter_background,
    foreground: values.foreground,
  };
}

function formatRatio(value) {
  return `${value.toFixed(2)}:1`;
}

function paletteLabel(file) {
  const filename = path.basename(file);
  return filename === "colors.toml"
    ? path.basename(path.dirname(file))
    : path.basename(file, path.extname(file));
}

function evaluatePalette(palette) {
  const accentForeground = deriveAccentForeground(palette);
  return [
    {
      id: "primary button text",
      foreground: accentForeground,
      background: palette.accent,
      minimum: 4.5,
      severity: "critical",
    },
    {
      id: "selection text",
      foreground: palette.foreground,
      background: palette.selection,
      minimum: 4.5,
      severity: "critical",
    },
    {
      id: "accent text on background",
      foreground: palette.accent,
      background: palette.background,
      minimum: 4.5,
      severity: "warning",
    },
    {
      id: "accent text on dark background",
      foreground: palette.accent,
      background: palette.background_dark,
      minimum: 4.5,
      severity: "warning",
    },
    {
      id: "accent text on light background",
      foreground: palette.accent,
      background: palette.background_light,
      minimum: 4.5,
      severity: "warning",
    },
    {
      id: "muted text on background",
      foreground: palette.foreground_muted,
      background: palette.background,
      minimum: 4.5,
      severity: "warning",
    },
    {
      id: "muted text on dark background",
      foreground: palette.foreground_muted,
      background: palette.background_dark,
      minimum: 4.5,
      severity: "warning",
    },
    {
      id: "muted text on light background",
      foreground: palette.foreground_muted,
      background: palette.background_light,
      minimum: 4.5,
      severity: "warning",
    },
    {
      id: "scrollbar thumb on track",
      foreground: palette.foreground_muted,
      background: palette.background_dark,
      minimum: 3,
      severity: "warning",
    },
  ].map(check => ({
    ...check,
    ratio: contrastRatio(check.foreground, check.background),
  }));
}

const requestedRoots = explicitRoots.length > 0
  ? explicitRoots
  : configuredRoots.length > 0
    ? configuredRoots
    : STOCK_ROOTS;
let files = requestedRoots.flatMap(discover);
let sourceDescription = requestedRoots.join(", ");
if (files.length === 0 && explicitRoots.length === 0 && configuredRoots.length === 0) {
  files = discover(FALLBACK_FIXTURE_ROOT);
  sourceDescription = `${FALLBACK_FIXTURE_ROOT} (fallback fixtures)`;
}
files = [...new Set(files)].sort();

if (files.length === 0) {
  if (strict) {
    console.error("Contrast validation failed: no colors.toml files were found.");
    process.exit(1);
  }
  console.log("Contrast validation skipped: no colors.toml files were found.");
  process.exit(0);
}

const failures = [];
const warnings = new Map();
for (const file of files) {
  let palette;
  try {
    palette = parseColors(file);
  } catch (error) {
    failures.push(`${file}: ${error.message}`);
    continue;
  }
  for (const check of evaluatePalette(palette)) {
    if (check.ratio >= check.minimum) continue;
    const label = `${check.id} (<${check.minimum}:1)`;
    const entry = warnings.get(label) || [];
    entry.push(`${paletteLabel(file)} ${formatRatio(check.ratio)}`);
    warnings.set(label, entry);
    if (check.severity === "critical") {
      failures.push(`${paletteLabel(file)}: ${check.id} ${formatRatio(check.ratio)}`);
    }
  }
}

console.log(`Contrast validation: ${files.length} palette(s) from ${sourceDescription}`);
for (const [label, entries] of warnings) {
  console.log(`WARN ${label}: ${entries.join(", ")}`);
}
if (failures.length > 0) {
  console.error(`FAIL ${failures.length} critical contrast check(s): ${failures.join("; ")}`);
  process.exit(1);
}
if (strict && warnings.size > 0) {
  console.error(`FAIL strict contrast mode: ${warnings.size} check group(s) below threshold`);
  process.exit(1);
}
console.log(
  warnings.size > 0
    ? `Contrast validation passed critical checks with ${warnings.size} warning group(s).`
    : "Contrast validation passed with no warnings.",
);
