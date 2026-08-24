/* SPDX-License-Identifier: GPL-3.0-only */
/* See NOTICE for the required Omazen project attribution terms. */

"use strict";

const COLOR_RE = /^#[0-9a-fA-F]{6}$/;

export const COLOR_KEYS = Object.freeze([
  "accent",
  "background",
  "background_dark",
  "background_light",
  "foreground",
  "foreground_muted",
  "selection",
  "border",
]);

const PALETTE_KEYS = Object.freeze(["schema_version", "mode", ...COLOR_KEYS]);

export function validatePalette(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("palette must be a JSON object");
  }
  const keys = Object.keys(value).sort();
  const expected = [...PALETTE_KEYS].sort();
  if (keys.length !== expected.length || keys.some((key, index) => key !== expected[index])) {
    throw new Error("palette contains missing or unknown keys");
  }
  if (value.schema_version !== 1) throw new Error("unsupported palette schema");
  if (value.mode !== "dark" && value.mode !== "light") throw new Error("invalid palette mode");

  const palette = { schema_version: 1, mode: value.mode };
  for (const key of COLOR_KEYS) {
    if (typeof value[key] !== "string" || !COLOR_RE.test(value[key])) {
      throw new Error(`invalid color: ${key}`);
    }
    palette[key] = value[key].toLowerCase();
  }
  return Object.freeze(palette);
}

export function validatePayload(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  if (value.enabled === false) return { enabled: false };
  if (value.enabled !== true || (value.mode !== "dark" && value.mode !== "light")) return null;
  const payload = { enabled: true, mode: value.mode };
  for (const key of COLOR_KEYS) {
    if (typeof value[key] !== "string" || !COLOR_RE.test(value[key])) return null;
    payload[key] = value[key].toLowerCase();
  }
  return payload;
}

export function actorPayload(palette, enabled) {
  if (!enabled || !palette) return { enabled: false };
  const payload = { enabled: true, mode: palette.mode };
  for (const key of COLOR_KEYS) payload[key] = palette[key];
  return payload;
}

export function setRootPalette(root, palette, enabled) {
  if (!enabled || !palette) {
    root.removeAttribute("data-omazen-enabled");
    root.removeAttribute("data-omazen-mode");
    root.style.removeProperty("color-scheme");
    for (const key of COLOR_KEYS) {
      root.style.removeProperty(`--omazen-${key.replaceAll("_", "-")}`);
    }
    return false;
  }

  root.setAttribute("data-omazen-enabled", "true");
  root.setAttribute("data-omazen-mode", palette.mode);
  root.style.setProperty("color-scheme", palette.mode);
  for (const key of COLOR_KEYS) {
    root.style.setProperty(`--omazen-${key.replaceAll("_", "-")}`, palette[key]);
  }
  return true;
}
