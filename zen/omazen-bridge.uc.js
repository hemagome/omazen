// ==UserScript==
// @name           Omazen privileged palette bridge
// @description    Applies a validated local Omazen palette to Zen chrome and internal pages.
// @version        0.1.11
// @author         Omazen contributors
// @include        main
// @WindowActor    Omazen
// @WindowActorMatches ["about:addons","about:config","about:debugging","about:devtools-toolbox","about:devtools-toolbox?*","about:downloads","about:home","about:logins","about:newtab","about:preferences","about:privatebrowsing","about:profiles","about:protections","about:support","about:translations","about:welcome","chrome://browser/content/aboutlogins/aboutLogins.html","chrome://browser/content/spotlight.html","chrome://devtools/content/*","chrome://global/content/commonDialog.xhtml","chrome://global/content/print.html","chrome://global/content/translations/about-translations.html"]
// ==/UserScript==

(() => {
  "use strict";

  const POLL_MS = 250;
  const MAX_PALETTE_BYTES = 2048;
  const MAX_LOG_BYTES = 131072;
  const STYLE_ID = "omazen-chrome-style";
  const CONTENT_STYLE_ID = "omazen-content-style";
  const VERSION = "0.1.11";
  const STYLE_URI = "chrome://userscripts/content/Omazen/omazen-chrome-v0.1.11.css";
  const CONTENT_STYLE_URI = "chrome://userscripts/content/Omazen/omazen-content-v0.1.11.css";
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
  const PLACES_ORGANIZER_URI = "chrome://browser/content/places/places.xhtml";
  const DEVTOOLS_TOOLBOX_URI = "chrome://devtools/content/framework/toolbox-window.xhtml";
  const ACTOR_CHROME_PREFIXES = Object.freeze([
    "chrome://browser/content/aboutlogins/aboutLogins.html",
    "chrome://browser/content/spotlight.html",
    "chrome://devtools/content/",
    "chrome://global/content/commonDialog.xhtml",
    "chrome://global/content/print.html",
    "chrome://global/content/translations/about-translations.html",
  ]);
  const AUXILIARY_WINDOW_TYPES = Object.freeze({
    "Browser:About": ABOUT_DIALOG_URI,
    "Places:Organizer": PLACES_ORGANIZER_URI,
    "devtools:toolbox": DEVTOOLS_TOOLBOX_URI,
  });
  let paletteSignature = "";
  let disabledState = null;
  let currentPalette = null;
  let contentPaletteSheet = null;
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

  function contentPaletteCss(palette) {
    const hover = `color-mix(in srgb, ${palette.background_light} 82%, ${palette.accent})`;
    const accentHover = `color-mix(in srgb, ${palette.accent} 82%, ${palette.foreground})`;
    return `
@-moz-document url("about:logins"), url-prefix("chrome://browser/content/aboutlogins/"),
  url("about:translations"), url-prefix("chrome://global/content/translations/"),
  url("about:debugging"), url-prefix("chrome://devtools/content/"),
  url("chrome://global/content/print.html") {
  :root {
    color-scheme: ${palette.mode} !important;
    --omazen-accent: ${palette.accent} !important;
    --omazen-background: ${palette.background} !important;
    --omazen-background-dark: ${palette.background_dark} !important;
    --omazen-background-light: ${palette.background_light} !important;
    --omazen-foreground: ${palette.foreground} !important;
    --omazen-foreground-muted: ${palette.foreground_muted} !important;
    --omazen-selection: ${palette.selection} !important;
    --omazen-border: ${palette.border} !important;
    --background-color-canvas: ${palette.background} !important;
    --background-color-box: ${palette.background_dark} !important;
    --background-color-box-info: ${palette.background_light} !important;
    --background-color-overlay: ${palette.background_dark} !important;
    --button-background-color: ${palette.background_light} !important;
    --button-background-color-hover: ${hover} !important;
    --button-background-color-active: ${palette.selection} !important;
    --button-background-color-primary: ${palette.accent} !important;
    --button-background-color-ghost-hover: ${palette.background_light} !important;
    --button-text-color: ${palette.foreground} !important;
    --button-text-color-hover: ${palette.foreground} !important;
    --button-text-color-primary: ${palette.background_dark} !important;
    --button-text-color-ghost: ${palette.foreground_muted} !important;
    --button-text-color-ghost-hover: ${palette.foreground} !important;
    --border-color: ${palette.border} !important;
    --border-color-selected: ${palette.accent} !important;
    --card-background-color: ${palette.background_dark} !important;
    --card-border-color: ${palette.border} !important;
    --color-accent-primary: ${palette.accent} !important;
    --color-accent-primary-hover: ${accentHover} !important;
    --link-color: ${palette.accent} !important;
    --link-color-hover: ${accentHover} !important;
    --link-color-active: ${palette.accent} !important;
    --link-color-visited: ${palette.accent} !important;
    --icon-color: ${palette.foreground_muted} !important;
    --input-text-background-color: ${palette.background_dark} !important;
    --input-text-border-color: ${palette.border} !important;
    --input-text-color: ${palette.foreground} !important;
    --text-color: ${palette.foreground} !important;
    --text-color-deemphasized: ${palette.foreground_muted} !important;
    --box-background: ${palette.background_dark} !important;
    --category-background-hover: ${palette.background_light} !important;
    --category-text: ${palette.foreground} !important;
    --category-text-selected: ${palette.accent} !important;
    --sidebar-text-color: ${palette.foreground} !important;
    --sidebar-selected-color: ${palette.accent} !important;
    --sidebar-background-hover: ${palette.background_light} !important;
    --card-separator-color: ${palette.border} !important;
    --theme-body-background: ${palette.background} !important;
    --theme-body-emphasized-background: ${palette.background_light} !important;
    --theme-sidebar-background: ${palette.background_dark} !important;
    --theme-toolbar-background: ${palette.background_dark} !important;
    --theme-toolbar-alternate-background: ${palette.background_light} !important;
    --theme-toolbar-color: ${palette.foreground} !important;
    --theme-toolbar-selected-color: ${palette.accent} !important;
    --theme-toolbar-hover: ${palette.background_light} !important;
    --theme-toolbar-separator: ${palette.border} !important;
    --theme-selection-background: ${palette.selection} !important;
    --theme-selection-color: ${palette.foreground} !important;
    --theme-splitter-color: ${palette.border} !important;
    --theme-icon-color: ${palette.foreground_muted} !important;
    --theme-icon-checked-color: ${palette.accent} !important;
    --theme-body-color: ${palette.foreground} !important;
    --theme-link-color: ${palette.accent} !important;
    --theme-text-color-alt: ${palette.foreground_muted} !important;
    --theme-text-color-strong: ${palette.foreground} !important;
    --theme-focus-outline-color: ${palette.accent} !important;
    background: ${palette.background} !important;
    color: ${palette.foreground} !important;
  }
  :is(a, .text-link), ::part(support-link) {
    color: ${palette.accent} !important;
  }
  :is(a, .text-link):hover, ::part(support-link):hover {
    color: ${accentHover} !important;
  }
  :is(a, .text-link):hover:active, ::part(support-link):hover:active {
    color: ${palette.accent} !important;
  }
  html, body, header, body > section {
    background-color: ${palette.background} !important;
    color: ${palette.foreground} !important;
  }
  login-list, .app__sidebar, .sidebar, .card, .debug-target-item {
    background-color: ${palette.background_dark} !important;
    color: ${palette.foreground} !important;
    border-color: ${palette.border} !important;
  }
  #print, .header-container, .body-container, .footer-container {
    background-color: ${palette.background} !important;
    color: ${palette.foreground} !important;
  }
  #print :is(select, input[type="number"], input[type="text"]),
  .toggle-group-label {
    background-color: ${palette.background_dark} !important;
    color: ${palette.foreground} !important;
    border-color: ${palette.border} !important;
  }
  .toggle-group-input:checked + .toggle-group-label {
    background-color: ${palette.accent} !important;
    color: ${palette.background_dark} !important;
    border-color: ${palette.accent} !important;
  }
  #print :is(input[type="radio"], input[type="checkbox"]) {
    accent-color: ${palette.accent} !important;
  }
  #print :is(hr, .twisty, #button-container) {
    border-color: ${palette.border} !important;
  }
  #open-dialog-link {
    color: ${palette.accent} !important;
  }
}`;
  }

  function syncContentPaletteSheet(palette, enabled) {
    const styleSheetService = Cc["@mozilla.org/content/style-sheet-service;1"].getService(
      Ci.nsIStyleSheetService,
    );
    if (contentPaletteSheet && styleSheetService.sheetRegistered(contentPaletteSheet, styleSheetService.USER_SHEET)) {
      styleSheetService.unregisterSheet(contentPaletteSheet, styleSheetService.USER_SHEET);
    }
    contentPaletteSheet = null;
    if (!enabled || !palette) return;
    contentPaletteSheet = Services.io.newURI(
      `data:text/css;charset=UTF-8,${encodeURIComponent(contentPaletteCss(palette))}`,
    );
    styleSheetService.loadAndRegisterSheet(contentPaletteSheet, styleSheetService.USER_SHEET);
  }

  function applyToAuxiliaryWindow(auxiliaryWindow, palette, enabled) {
    const auxiliaryDocument = auxiliaryWindow?.document;
    const root = auxiliaryDocument?.documentElement;
    const expectedUri = AUXILIARY_WINDOW_TYPES[root?.getAttribute("windowtype")];
    if (!root || !expectedUri || auxiliaryWindow.location.href !== expectedUri) return;

    let link = auxiliaryDocument.getElementById(STYLE_ID);
    if (!link) {
      link = auxiliaryDocument.createElementNS("http://www.w3.org/1999/xhtml", "link");
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

  function isActorInternalUri(uri) {
    return uri?.startsWith("about:") || ACTOR_CHROME_PREFIXES.some((prefix) => uri?.startsWith(prefix));
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
        if (!isActorInternalUri(spec)) continue;
        const global = browser.browsingContext?.currentWindowGlobal;
        global?.getActor("Omazen")?.sendAsyncMessage("Omazen:Apply", payload);
      } catch (_error) {
        // Non-matching internal documents do not have an Omazen actor.
      }
    }
    for (const windowType of Object.keys(AUXILIARY_WINDOW_TYPES)) {
      const auxiliaryWindows = Services.wm.getEnumerator(windowType);
      while (auxiliaryWindows.hasMoreElements()) {
        applyToAuxiliaryWindow(auxiliaryWindows.getNext(), palette, enabled);
      }
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
    syncContentPaletteSheet(palette, true);
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
    syncContentPaletteSheet(currentPalette, false);
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
  const auxiliaryWindowObserver = {
    observe(subject, topic) {
      if (topic !== "domwindowopened") return;
      subject.addEventListener(
        "DOMContentLoaded",
        () => applyToAuxiliaryWindow(subject, currentPalette, !disabledState),
        { once: true },
      );
    },
  };
  Services.obs.addObserver(auxiliaryWindowObserver, "domwindowopened");
  window.addEventListener(
    "unload",
    () => Services.obs.removeObserver(auxiliaryWindowObserver, "domwindowopened"),
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
