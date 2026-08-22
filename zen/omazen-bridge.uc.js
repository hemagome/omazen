// ==UserScript==
// @name           Omazen privileged palette bridge
// @description    Applies a validated local Omazen palette to Zen chrome and internal pages.
// @version        0.1.2
// @author         Omazen contributors
// @include        main
// @WindowActor    Omazen
// @WindowActorMatches ["about:addons","about:config","about:downloads","about:home","about:newtab","about:preferences","about:privatebrowsing","about:profiles","about:protections","about:support","about:welcome"]
// ==/UserScript==

(() => {
  "use strict";

  const POLL_MS = 250;
  const MAX_PALETTE_BYTES = 2048;
  const MAX_LOG_BYTES = 131072;
  const STYLE_ID = "omazen-chrome-style";
  const VERSION = "0.1.2";
  const STYLE_URI = "chrome://userscripts/content/Omazen/omazen-chrome-v0.1.2.css";
  const STATE_LEAF = ".local/state/omazen";
  const COLOR_RE = /^#[0-9a-fA-F]{6}$/;
  const COLOR_KEYS = Object.freeze([
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
  let paletteSignature = "";
  let disabledState = null;
  let currentPalette = null;

  function stateDirectory() {
    const configured = Services.env.get("XDG_STATE_HOME");
    const base = configured || Services.dirsvc.get("Home", Ci.nsIFile).path + "/.local/state";
    const directory = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
    directory.initWithPath(base + "/omazen");
    return directory;
  }

  function stateFile(leafName) {
    const file = stateDirectory().clone();
    file.append(leafName);
    return file;
  }

  function appendLog(level, message) {
    const line = `${new Date().toISOString()} [${level}] ${message}\n`;
    try {
      const file = stateFile("bridge.log");
      if (file.exists() && file.fileSize > MAX_LOG_BYTES) file.remove(false);
      const stream = Cc["@mozilla.org/network/file-output-stream;1"].createInstance(
        Ci.nsIFileOutputStream,
      );
      stream.init(file, 0x02 | 0x08 | 0x10, 0o600, 0);
      stream.write(line, line.length);
      stream.close();
    } catch (error) {
      console.error("Omazen log write failed", error);
    }
  }

  function readText(file) {
    if (file.fileSize < 2 || file.fileSize > MAX_PALETTE_BYTES) {
      throw new Error("palette size outside accepted range");
    }
    const input = Cc["@mozilla.org/network/file-input-stream;1"].createInstance(
      Ci.nsIFileInputStream,
    );
    const converter = Cc["@mozilla.org/intl/converter-input-stream;1"].createInstance(
      Ci.nsIConverterInputStream,
    );
    input.init(file, -1, 0, 0);
    converter.init(
      input,
      "UTF-8",
      4096,
      Ci.nsIConverterInputStream.DEFAULT_REPLACEMENT_CHARACTER,
    );
    try {
      let text = "";
      const chunk = {};
      while (converter.readString(4096, chunk)) text += chunk.value;
      return text;
    } finally {
      converter.close();
    }
  }

  function validatePalette(value) {
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

  function ensureChromeStyle() {
    let link = document.getElementById(STYLE_ID);
    if (link) return link;
    link = document.createElementNS("http://www.w3.org/1999/xhtml", "link");
    link.id = STYLE_ID;
    link.rel = "stylesheet";
    link.href = STYLE_URI;
    document.documentElement.appendChild(link);
    return link;
  }

  function writePalettePrefs(palette, enabled) {
    Services.prefs.setBoolPref("omazen.enabled", enabled);
    if (!palette) return;
    Services.prefs.setStringPref("omazen.palette.mode", palette.mode);
    for (const key of COLOR_KEYS) {
      Services.prefs.setStringPref(`omazen.palette.${key}`, palette[key]);
    }
  }

  function actorPayload(palette, enabled) {
    if (!enabled || !palette) return { enabled: false };
    const payload = { enabled: true, mode: palette.mode };
    for (const key of COLOR_KEYS) payload[key] = palette[key];
    return payload;
  }

  function broadcastToInternalPages(palette, enabled) {
    const payload = actorPayload(palette, enabled);
    if (!window.gBrowser) return;
    for (const tab of window.gBrowser.tabs) {
      try {
        const browser = tab.linkedBrowser;
        if (!browser?.currentURI?.spec?.startsWith("about:")) continue;
        const global = browser.browsingContext?.currentWindowGlobal;
        global?.getActor("Omazen")?.sendAsyncMessage("Omazen:Apply", payload);
      } catch (_error) {
        // Non-matching about pages do not have an Omazen actor.
      }
    }
  }

  function applyPalette(palette) {
    ensureChromeStyle();
    const root = document.documentElement;
    root.setAttribute("data-omazen-enabled", "true");
    root.setAttribute("data-omazen-mode", palette.mode);
    root.style.setProperty("color-scheme", palette.mode);
    root.style.setProperty(
      "--omazen-transition-duration",
      Services.prefs.getBoolPref("omazen.transitions.enabled", true) ? "180ms" : "0ms",
    );
    for (const key of COLOR_KEYS) {
      root.style.setProperty(`--omazen-${key.replaceAll("_", "-")}`, palette[key]);
    }
    currentPalette = palette;
    writePalettePrefs(palette, true);
    broadcastToInternalPages(palette, true);
    appendLog("INFO", `PALETTE_APPLIED accent=${palette.accent} mode=${palette.mode}`);
    window.setTimeout(() => {
      const primary = getComputedStyle(root).getPropertyValue("--zen-primary-color").trim();
      if (primary === palette.accent) appendLog("INFO", `CHROME_CSS_APPLIED primary=${primary}`);
      else appendLog("ERROR", "chrome stylesheet did not expose the expected primary color");

      const styleProbe = (selector) => {
        const element = document.querySelector(selector);
        if (!element) return `${selector}=missing`;
        const style = getComputedStyle(element);
        const background = style.backgroundColor.replaceAll(" ", "");
        const toolbar = style.getPropertyValue("--zen-toolbar-element-bg").trim().replaceAll(" ", "");
        const base = style.getPropertyValue("--zen-urlbar-background-base").trim().replaceAll(" ", "");
        return `${selector}=${background}|toolbar:${toolbar}|base:${base}`;
      };
      appendLog(
        "INFO",
        `CHROME_STYLE_PROBE ${styleProbe(".urlbar-background")} ${styleProbe(".urlbar-input-container")} ${styleProbe("#urlbar")}`,
      );
    }, 100);
  }

  function disablePalette() {
    const root = document.documentElement;
    root.removeAttribute("data-omazen-enabled");
    root.removeAttribute("data-omazen-mode");
    root.style.removeProperty("color-scheme");
    root.style.removeProperty("--omazen-transition-duration");
    for (const key of COLOR_KEYS) {
      root.style.removeProperty(`--omazen-${key.replaceAll("_", "-")}`);
    }
    writePalettePrefs(currentPalette, false);
    broadcastToInternalPages(currentPalette, false);
  }

  function sync() {
    const disabledFile = stateFile("disabled");
    const nextDisabled = disabledFile.exists();
    if (nextDisabled !== disabledState) {
      disabledState = nextDisabled;
      if (disabledState) {
        disablePalette();
        appendLog("INFO", "DISABLED");
      } else if (currentPalette) {
        applyPalette(currentPalette);
      }
    }
    if (disabledState) return;

    try {
      const file = stateFile("palette.json");
      if (!file.exists() || !file.isFile()) return;
      const signature = `${file.lastModifiedTime}:${file.fileSize}`;
      if (signature === paletteSignature) return;
      paletteSignature = signature;
      const palette = validatePalette(JSON.parse(readText(file)));
      applyPalette(palette);
    } catch (error) {
      appendLog("ERROR", error.message);
    }
  }

  ensureChromeStyle();
  appendLog("INFO", `BRIDGE_LOADED version=${VERSION}`);
  sync();
  window.setInterval(sync, POLL_MS);
})();
