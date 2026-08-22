// ==UserScript==
// @name           Omazen privileged palette bridge
// @description    Applies a validated local Omazen palette to Zen chrome and internal pages.
// @version        0.1.6
// @author         Omazen contributors
// @include        main
// @WindowActor    Omazen
// @WindowActorMatches ["about:addons","about:config","about:downloads","about:home","about:newtab","about:preferences","about:privatebrowsing","about:profiles","about:protections","about:support","about:welcome","chrome://browser/content/spotlight.html","chrome://global/content/commonDialog.xhtml"]
// ==/UserScript==

(() => {
  "use strict";

  const POLL_MS = 250;
  const MAX_PALETTE_BYTES = 2048;
  const MAX_LOG_BYTES = 131072;
  const STYLE_ID = "omazen-chrome-style";
  const CONTENT_STYLE_ID = "omazen-content-style";
  const VERSION = "0.1.6";
  const STYLE_URI = "chrome://userscripts/content/Omazen/omazen-chrome-v0.1.6.css";
  const CONTENT_STYLE_URI = "chrome://userscripts/content/Omazen/omazen-content-v0.1.6.css";
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
  const SPOTLIGHT_URI = "chrome://browser/content/spotlight.html";
  const COMMON_DIALOG_URI = "chrome://global/content/commonDialog.xhtml";
  const ABOUT_DIALOG_URI = "chrome://browser/content/aboutDialog.xhtml";
  let paletteSignature = "";
  let disabledState = null;
  let currentPalette = null;
  let broadcastTimer = 0;

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

  function applyToAboutDialog(aboutWindow, palette, enabled) {
    const aboutDocument = aboutWindow?.document;
    const root = aboutDocument?.documentElement;
    if (!root || aboutWindow.location.href !== ABOUT_DIALOG_URI) return;

    let link = aboutDocument.getElementById(STYLE_ID);
    if (!link) {
      link = aboutDocument.createElementNS("http://www.w3.org/1999/xhtml", "link");
      link.id = STYLE_ID;
      link.rel = "stylesheet";
      link.href = STYLE_URI;
      root.appendChild(link);
    }

    if (!enabled || !palette) {
      root.removeAttribute("data-omazen-enabled");
      root.removeAttribute("data-omazen-mode");
      root.style.removeProperty("color-scheme");
      for (const key of COLOR_KEYS) {
        root.style.removeProperty(`--omazen-${key.replaceAll("_", "-")}`);
      }
      return;
    }

    root.setAttribute("data-omazen-enabled", "true");
    root.setAttribute("data-omazen-mode", palette.mode);
    root.style.setProperty("color-scheme", palette.mode);
    for (const key of COLOR_KEYS) {
      root.style.setProperty(`--omazen-${key.replaceAll("_", "-")}`, palette[key]);
    }
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

  function applyToInternalDialogFrame(frame, palette, enabled) {
    const contentDocument = frame?.contentDocument;
    const root = contentDocument?.documentElement;
    const uri = contentDocument?.location?.href;
    if (!root || (!uri.startsWith(SPOTLIGHT_URI) && !uri.startsWith(COMMON_DIALOG_URI))) {
      return;
    }
    const wasEnabled = root.getAttribute("data-omazen-enabled") === "true";

    let link = contentDocument.getElementById(CONTENT_STYLE_ID);
    if (!link) {
      link = contentDocument.createElementNS("http://www.w3.org/1999/xhtml", "link");
      link.id = CONTENT_STYLE_ID;
      link.rel = "stylesheet";
      link.href = CONTENT_STYLE_URI;
      root.appendChild(link);
    }

    if (!enabled || !palette) {
      root.removeAttribute("data-omazen-enabled");
      root.removeAttribute("data-omazen-mode");
      root.style.removeProperty("color-scheme");
      for (const key of COLOR_KEYS) {
        root.style.removeProperty(`--omazen-${key.replaceAll("_", "-")}`);
      }
      contentDocument
        .getElementById("commonDialog")
        ?.getButton?.("accept")
        ?.part.remove("omazen-primary-button");
      return;
    }

    root.setAttribute("data-omazen-enabled", "true");
    root.setAttribute("data-omazen-mode", palette.mode);
    root.style.setProperty("color-scheme", palette.mode);
    for (const key of COLOR_KEYS) {
      root.style.setProperty(`--omazen-${key.replaceAll("_", "-")}`, palette[key]);
    }
    const commonDialog = contentDocument.getElementById("commonDialog");
    const acceptButton = commonDialog?.getButton?.("accept");
    if (acceptButton) acceptButton.part.add("omazen-primary-button");
    if (!wasEnabled) {
      const kind = uri.startsWith(COMMON_DIALOG_URI) ? "COMMON_DIALOG" : "SPOTLIGHT";
      appendLog("INFO", `${kind}_PALETTE_APPLIED uri=${uri}`);
      window.setTimeout(() => {
        const surface = contentDocument.querySelector(".main-content, #commonDialog");
        const primary = contentDocument.querySelector("button.primary") || acceptButton;
        const surfaceColor = surface ? contentDocument.defaultView.getComputedStyle(surface).backgroundColor : "missing";
        const primaryColor = primary ? contentDocument.defaultView.getComputedStyle(primary).backgroundColor : "missing";
        appendLog("INFO", `${kind}_STYLE_PROBE surface=${surfaceColor} primary=${primaryColor}`);
      }, 250);
    }
  }

  function broadcastToInternalPages(palette, enabled) {
    const payload = actorPayload(palette, enabled);
    const browsers = new Set(document.querySelectorAll("browser"));
    const dialogFrame = window.gDialogBox?.dialog?._frame;
    if (dialogFrame) {
      browsers.add(dialogFrame);
      applyToInternalDialogFrame(dialogFrame, palette, enabled);
    }
    if (window.gBrowser) {
      for (const tab of window.gBrowser.tabs) {
        const browser = tab.linkedBrowser;
        browsers.add(browser);
        const tabDialogBox = window.gBrowser.getTabDialogBox(browser);
        const tabDialogFrame = tabDialogBox?._tabDialogManager?._topDialog?._frame;
        if (tabDialogFrame) {
          browsers.add(tabDialogFrame);
          applyToInternalDialogFrame(tabDialogFrame, palette, enabled);
        }
        const contentDialogFrame = tabDialogBox?._contentDialogManager?._topDialog?._frame;
        if (contentDialogFrame) {
          browsers.add(contentDialogFrame);
          applyToInternalDialogFrame(contentDialogFrame, palette, enabled);
        }
      }
    }
    for (const browser of browsers) {
      try {
        const spec = browser?.currentURI?.spec;
        if (
          !spec?.startsWith("about:") &&
          !spec?.startsWith(SPOTLIGHT_URI) &&
          !spec?.startsWith(COMMON_DIALOG_URI)
        ) continue;
        const global = browser.browsingContext?.currentWindowGlobal;
        global?.getActor("Omazen")?.sendAsyncMessage("Omazen:Apply", payload);
      } catch (_error) {
        // Non-matching internal documents do not have an Omazen actor.
      }
    }
    const aboutWindows = Services.wm.getEnumerator("Browser:About");
    while (aboutWindows.hasMoreElements()) {
      applyToAboutDialog(aboutWindows.getNext(), palette, enabled);
    }
  }

  function scheduleInternalPageBroadcast() {
    if (broadcastTimer || !currentPalette) return;
    broadcastTimer = window.setTimeout(() => {
      broadcastTimer = 0;
      broadcastToInternalPages(currentPalette, !disabledState);
    }, 50);
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
  const aboutWindowObserver = {
    observe(subject, topic) {
      if (topic !== "domwindowopened") return;
      subject.addEventListener(
        "DOMContentLoaded",
        () => applyToAboutDialog(subject, currentPalette, !disabledState),
        { once: true },
      );
    },
  };
  Services.obs.addObserver(aboutWindowObserver, "domwindowopened");
  window.addEventListener(
    "unload",
    () => Services.obs.removeObserver(aboutWindowObserver, "domwindowopened"),
    { once: true },
  );
  new MutationObserver(scheduleInternalPageBroadcast).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
  appendLog("INFO", `BRIDGE_LOADED version=${VERSION}`);
  sync();
  window.setInterval(sync, POLL_MS);
})();
