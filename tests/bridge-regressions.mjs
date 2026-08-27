/* SPDX-License-Identifier: GPL-3.0-only */
/* See NOTICE for the required Omazen project attribution terms. */

import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import * as paletteModule from "../zen/Omazen/OmazenPalette.sys.mjs";

const stateRoot = "/home/test/.local/state/omazen";
const files = new Map([
  [`${stateRoot}/bridge.log`, { size: 131060 }],
  [`${stateRoot}/palette.json`, { size: 300, modified: 1 }],
]);
const initialPalette = {
  schema_version: 1,
  mode: "dark",
  accent: "#112233",
  background: "#223344",
  background_dark: "#334455",
  background_light: "#445566",
  foreground: "#ddeeff",
  foreground_muted: "#aabbcc",
  selection: "#556677",
  border: "#667788",
};
let paletteText = JSON.stringify(initialPalette);
const logLines = [];

assert.deepEqual(
  paletteModule.validatePalette({ ...initialPalette, accent: "#ABCDEF" }),
  { ...initialPalette, accent: "#abcdef" },
  "shared palette validation should normalize colors",
);
assert.throws(
  () => paletteModule.validatePalette({ ...initialPalette, unexpected: true }),
  /missing or unknown keys/,
  "shared palette validation should reject unknown keys",
);
assert.equal(
  paletteModule.validatePayload({ enabled: true, ...initialPalette, accent: "invalid" }),
  null,
  "shared actor validation should reject invalid colors",
);
assert.equal(
  paletteModule.contrastRatio("#000000", "#ffffff"),
  21,
  "shared contrast calculation should use the WCAG black/white ratio",
);
assert.equal(
  paletteModule.deriveAccentForeground({
    accent: "#56949f",
    background_dark: "#ede7e1",
    foreground: "#575279",
  }),
  "#000000",
  "accent foreground should fall back to black for a light mid-tone accent",
);
assert.equal(
  paletteModule.deriveAccentForeground({
    accent: "#1e66f5",
    background_dark: "#e3e4e8",
    foreground: "#4c4f69",
  }),
  "#ffffff",
  "accent foreground should fall back to white when black is insufficient",
);

class FakeFile {
  constructor(path = "") {
    this.path = path;
  }

  initWithPath(path) {
    this.path = path;
  }

  clone() {
    return new FakeFile(this.path);
  }

  append(leaf) {
    this.path += `/${leaf}`;
  }

  exists() {
    return files.has(this.path);
  }

  isFile() {
    return this.exists();
  }

  get fileSize() {
    return files.get(this.path)?.size ?? 0;
  }

  get lastModifiedTime() {
    return files.get(this.path)?.modified ?? 0;
  }

  remove() {
    files.delete(this.path);
  }

  moveTo(_parent, leaf) {
    const entry = files.get(this.path);
    files.delete(this.path);
    this.path = `${this.path.slice(0, this.path.lastIndexOf("/") + 1)}${leaf}`;
    files.set(this.path, entry);
  }
}

class FakeOutputStream {
  init(file) {
    this.file = file;
  }

  write(line, length) {
    const current = files.get(this.file.path)?.size ?? 0;
    files.set(this.file.path, { size: current + length });
    logLines.push(line);
  }

  close() {}
}

class FakeConverterInputStream {
  init() {
    this.read = false;
  }

  readString(_length, chunk) {
    if (this.read) return 0;
    this.read = true;
    chunk.value = paletteText;
    return paletteText.length;
  }

  close() {}
}

const observers = [];
class FakeMutationObserver {
  constructor(callback) {
    this.callback = callback;
    this.disconnected = false;
    observers.push(this);
  }

  observe() {}

  disconnect() {
    this.disconnected = true;
  }
}

const styleValues = new Map();
const attributes = new Map();
const links = new Map();
const root = {
  appendChild(link) {
    links.set(link.id, link);
  },
  removeAttribute(name) {
    attributes.delete(name);
  },
  setAttribute(name, value) {
    attributes.set(name, value);
  },
  style: {
    removeProperty(name) {
      styleValues.delete(name);
    },
    setProperty(name, value) {
      styleValues.set(name, value);
    },
  },
};

let browserQueries = 0;
const sentMessages = [];
const browser = {
  currentURI: { spec: "about:preferences" },
  browsingContext: {
    currentWindowGlobal: {
      getActor: () => ({
        sendAsyncMessage(name, payload) {
          sentMessages.push({ name, payload });
        },
      }),
    },
  },
};
const document = {
  documentElement: root,
  createElementNS() {
    return {};
  },
  getElementById(id) {
    return links.get(id) ?? null;
  },
  querySelector() {
    return null;
  },
  querySelectorAll(selector) {
    if (selector === "browser") browserQueries += 1;
    return selector === "browser" ? [browser] : [];
  },
};

let nextTimer = 1;
const timeouts = new Map();
const intervals = new Map();
const intervalDelays = new Map();
let unloadHandler;
const window = {
  addEventListener(name, callback) {
    if (name === "unload") unloadHandler = callback;
  },
  clearInterval(id) {
    intervals.delete(id);
    intervalDelays.delete(id);
  },
  clearTimeout(id) {
    timeouts.delete(id);
  },
  setInterval(callback, delay) {
    const id = nextTimer++;
    intervals.set(id, callback);
    intervalDelays.set(id, delay);
    return id;
  },
  setTimeout(callback) {
    const id = nextTimer++;
    timeouts.set(id, callback);
    return id;
  },
};

function createAuxiliaryWindow(windowType, href) {
  const auxiliaryAttributes = new Map([["windowtype", windowType]]);
  const auxiliaryLinks = new Map();
  let loaded;
  const auxiliaryRoot = {
    appendChild(link) {
      auxiliaryLinks.set(link.id, link);
    },
    getAttribute(name) {
      return auxiliaryAttributes.get(name) ?? null;
    },
    removeAttribute(name) {
      auxiliaryAttributes.delete(name);
    },
    setAttribute(name, value) {
      auxiliaryAttributes.set(name, value);
    },
    style: {
      removeProperty() {},
      setProperty() {},
    },
  };
  return {
    attributes: auxiliaryAttributes,
    document: {
      documentElement: auxiliaryRoot,
      createElementNS: () => ({}),
      getElementById: id => auxiliaryLinks.get(id) ?? null,
    },
    fireLoaded() {
      loaded?.();
    },
    location: { href },
    addEventListener(name, callback) {
      if (name === "DOMContentLoaded") loaded = callback;
    },
  };
}

const existingLibrary = createAuxiliaryWindow(
  "Places:Organizer",
  "chrome://browser/content/places/places.xhtml",
);
const auxiliaryWindows = new Map([["Places:Organizer", [existingLibrary]]]);
const enumeratorFor = values => {
  let index = 0;
  return {
    hasMoreElements: () => index < values.length,
    getNext: () => values[index++],
  };
};
let auxiliaryObserver;
let auxiliaryObserverRemoved = false;
const styleSheetService = {
  USER_SHEET: 1,
  registered: new Set(),
  loadAndRegisterSheet(sheet) {
    this.registered.add(sheet);
  },
  sheetRegistered(sheet) {
    return this.registered.has(sheet);
  },
  unregisterSheet(sheet) {
    this.registered.delete(sheet);
  },
};
const prefs = new Map();
const Services = {
  dirsvc: { get: () => ({ path: "/home/test" }) },
  env: { get: () => "" },
  io: { newURI: value => value },
  obs: {
    addObserver(observer, topic) {
      if (topic === "domwindowopened") auxiliaryObserver = observer;
    },
    removeObserver(observer, topic) {
      if (topic === "domwindowopened" && observer === auxiliaryObserver) {
        auxiliaryObserverRemoved = true;
      }
    },
  },
  prefs: {
    getBoolPref: (name, fallback) => prefs.get(name) ?? fallback,
    setBoolPref(name, value) {
      prefs.set(name, value);
    },
    setStringPref(name, value) {
      prefs.set(name, value);
    },
  },
  wm: { getEnumerator: type => enumeratorFor(auxiliaryWindows.get(type) ?? []) },
};

const Cc = new Proxy({}, {
  get(_target, contract) {
    if (contract === "@mozilla.org/file/local;1") {
      return { createInstance: () => new FakeFile() };
    }
    if (contract === "@mozilla.org/network/file-output-stream;1") {
      return { createInstance: () => new FakeOutputStream() };
    }
    if (contract === "@mozilla.org/network/file-input-stream;1") {
      return { createInstance: () => ({ init() {} }) };
    }
    if (contract === "@mozilla.org/intl/converter-input-stream;1") {
      return { createInstance: () => new FakeConverterInputStream() };
    }
    if (contract === "@mozilla.org/content/style-sheet-service;1") {
      return { getService: () => styleSheetService };
    }
    throw new Error(`unexpected contract: ${String(contract)}`);
  },
});
const Ci = {
  nsIConverterInputStream: { DEFAULT_REPLACEMENT_CHARACTER: 0 },
  nsIStyleSheetService: {},
};

let computedPrimary = "#112233";
let watcherCallback = null;
let watcherUnsubscribed = false;

const source = fs.readFileSync(new URL("../zen/omazen-bridge.uc.js", import.meta.url), "utf8");
vm.runInNewContext(source, {
  Cc,
  Ci,
  ChromeUtils: {
    importESModule(uri) {
      if (uri === "chrome://userscripts/content/Omazen/OmazenPalette.sys.mjs") {
        return paletteModule;
      }
      if (uri === "chrome://userscripts/content/Omazen/OmazenWatcher.sys.mjs") {
        return {
          subscribePaletteWatcher(callback) {
            watcherCallback = callback;
            return () => {
              watcherUnsubscribed = true;
            };
          },
        };
      }
      assert.fail(`unexpected bridge module import: ${uri}`);
    },
  },
  Date,
  JSON,
  Map,
  MutationObserver: FakeMutationObserver,
  Object,
  Services,
  Set,
  URL,
  console,
  document,
  encodeURIComponent,
  getComputedStyle: () => ({
    backgroundColor: "rgb(17,34,51)",
    getPropertyValue: name => (name === "--zen-primary-color" ? computedPrimary : "#112233"),
  }),
  window,
}, { filename: "omazen-bridge.uc.js" });

assert.ok(files.has(`${stateRoot}/bridge.log.1`), "oversized log should rotate to bridge.log.1");
assert.ok(files.has(`${stateRoot}/bridge.log`), "logging should continue in a fresh bridge.log");
assert.equal(observers.length, 1, "bridge should install one internal-page observer");
assert.equal(intervals.size, 1, "bridge should install one palette poll timer");
assert.equal([...intervalDelays.values()][0], 250, "bridge should poll quickly until the watcher is ready");
assert.equal(typeof watcherCallback, "function", "bridge should subscribe to palette watcher events");
watcherCallback({ type: "ready", backend: "inotify" });
assert.equal(intervals.size, 1, "watcher readiness should retain one fallback poll timer");
assert.equal([...intervalDelays.values()][0], 5000, "ready watcher should reduce fallback polling frequency");
assert.ok(logLines.some(line => line.includes("WATCHER_READY backend=inotify")), "watcher readiness should be logged");
assert.equal(attributes.get("data-omazen-enabled"), "true", "initial palette should enable chrome");
assert.equal(styleValues.get("--omazen-accent"), initialPalette.accent, "initial palette should style chrome");
assert.equal(
  styleValues.get("--omazen-accent-foreground"),
  paletteModule.deriveAccentForeground(initialPalette),
  "initial palette should derive an accessible accent foreground",
);
assert.equal(prefs.get("omazen.enabled"), true, "initial palette should enable actor preferences");
assert.equal(styleSheetService.registered.size, 1, "initial palette should register the content sheet");
assert.equal(
  existingLibrary.attributes.get("data-omazen-enabled"),
  "true",
  "startup broadcast should style existing auxiliary windows",
);
const lateAbout = createAuxiliaryWindow(
  "Browser:About",
  "chrome://browser/content/aboutDialog.xhtml",
);
auxiliaryObserver.observe(lateAbout, "domwindowopened");
lateAbout.fireLoaded();
assert.equal(
  lateAbout.attributes.get("data-omazen-enabled"),
  "true",
  "window observer should style late auxiliary windows",
);
const registeredSheet = [...styleSheetService.registered][0];
const generatedCss = decodeURIComponent(registeredSheet.slice(registeredSheet.indexOf(",") + 1));
assert.match(generatedCss, /@-moz-document url\("about:logins"\)/, "sheet should scope internal pages");
assert.match(generatedCss, /url-prefix\("https:\/\/"\)/, "sheet should scope web scrollbars");
assert.match(generatedCss, /scrollbar-color: #aabbcc #334455/, "sheet should map scrollbar colors");
assert.match(
  generatedCss,
  new RegExp(`--omazen-accent-foreground: ${paletteModule.deriveAccentForeground(initialPalette)} !important`),
  "sheet should expose the derived accent foreground",
);
assert.match(
  generatedCss,
  new RegExp(`--button-text-color-primary: ${paletteModule.deriveAccentForeground(initialPalette)} !important`),
  "sheet should use the derived accent foreground for primary buttons",
);
assert.match(
  generatedCss,
  new RegExp(`\\.toggle-group-input:checked \\+ \\.toggle-group-label \\{[\\s\\S]*color: ${paletteModule.deriveAccentForeground(initialPalette)} !important`),
  "sheet should use the derived accent foreground for Print toggles",
);
assert.match(generatedCss, /--button-text-color-menu: var\(--omazen-action-text\)/, "sheet should map action text");
assert.match(generatedCss, /\.toggle-group-input:checked \+ \.toggle-group-label/, "sheet should style Print orientation");
assert.match(generatedCss, /#open-dialog-link/, "sheet should style the system-dialog link");
assert.deepEqual(
  sentMessages.at(-1),
  { name: "Omazen:Apply", payload: { enabled: true, mode: "dark", ...Object.fromEntries(
    paletteModule.COLOR_KEYS.map(key => [key, initialPalette[key]]),
  ) } },
  "initial palette should be sent to matching internal actors",
);
const initialDiagnostic = timeouts.values().next().value;
timeouts.clear();
initialDiagnostic();
assert.ok(logLines.some(line => line.includes("CHROME_CSS_APPLIED primary=#112233")), "initial CSS probe should pass");
assert.ok(logLines.some(line => line.includes("profile=p")), "bridge diagnostics should identify the profile without logging its path");

timeouts.clear();
browserQueries = 0;
observers[0].callback([{ addedNodes: [{ localName: "div", querySelector: () => null }] }]);
assert.equal(timeouts.size, 0, "irrelevant mutations should not schedule a broadcast");

observers[0].callback([{ addedNodes: [{ localName: "browser" }] }]);
observers[0].callback([{ addedNodes: [{ querySelector: () => ({ localName: "browser" }) }] }]);
assert.equal(timeouts.size, 1, "browser mutations should schedule one debounced broadcast");

const scheduledBroadcast = timeouts.values().next().value;
timeouts.clear();
scheduledBroadcast();
assert.equal(browserQueries, 1, "scheduled broadcast should scan browser elements once");

const poll = intervals.values().next().value;
files.set(`${stateRoot}/disabled`, { size: 0 });
watcherCallback({ type: "change", leaf: "disabled", events: "CREATE" });
let watcherSync = [...timeouts.values()].at(-1);
timeouts.clear();
watcherSync();
assert.equal(attributes.has("data-omazen-enabled"), false, "disabled marker should clear chrome state");
assert.equal(styleValues.has("--omazen-accent"), false, "disabled marker should clear palette variables");
assert.equal(
  styleValues.has("--omazen-accent-foreground"),
  false,
  "disabled marker should clear the derived accent foreground",
);
assert.equal(prefs.get("omazen.enabled"), false, "disabled marker should disable actor preferences");
assert.equal(styleSheetService.registered.size, 0, "disabled marker should unregister content CSS");
assert.deepEqual(sentMessages.at(-1), { name: "Omazen:Apply", payload: { enabled: false } });

const updatedPalette = { ...initialPalette, mode: "light", accent: "#abcdef" };
paletteText = JSON.stringify(updatedPalette);
files.set(`${stateRoot}/palette.json`, { size: paletteText.length, modified: 2 });
files.delete(`${stateRoot}/disabled`);
const applicationsBeforeEnable = logLines.filter(line => line.includes("PALETTE_APPLIED")).length;
watcherCallback({ type: "change", leaf: "palette.json", events: "MOVED_TO" });
watcherSync = [...timeouts.values()].at(-1);
timeouts.clear();
watcherSync();
assert.equal(attributes.get("data-omazen-mode"), "light", "re-enable should apply the new mode");
assert.equal(styleValues.get("--omazen-accent"), "#abcdef", "re-enable should apply the new accent");
assert.equal(
  styleValues.get("--omazen-accent-foreground"),
  paletteModule.deriveAccentForeground(updatedPalette),
  "re-enable should recalculate the derived accent foreground",
);
assert.equal(prefs.get("omazen.enabled"), true, "re-enable should restore actor preferences");
assert.equal(sentMessages.at(-1).payload.accent, "#abcdef", "updated palette should reach actors");
assert.equal(
  logLines.filter(line => line.includes("PALETTE_APPLIED")).length,
  applicationsBeforeEnable + 1,
  "re-enable with a regenerated palette should apply only the new palette",
);
computedPrimary = "#000000";
let retryDiagnostic = [...timeouts.values()].at(-1);
timeouts.clear();
retryDiagnostic();
assert.equal(timeouts.size, 1, "CSS diagnostic should retry after a transient mismatch");
computedPrimary = "#abcdef";
retryDiagnostic = timeouts.values().next().value;
timeouts.clear();
retryDiagnostic();
assert.ok(logLines.some(line => line.includes("CHROME_CSS_APPLIED primary=#abcdef")), "CSS retry should recover after the stylesheet loads");

paletteText = JSON.stringify({ ...updatedPalette, unexpected: true });
files.set(`${stateRoot}/palette.json`, { size: paletteText.length, modified: 3 });
watcherCallback({ type: "change", leaf: "palette.json", events: "MOVED_TO" });
watcherSync = [...timeouts.values()].at(-1);
timeouts.clear();
watcherSync();
assert.equal(styleValues.get("--omazen-accent"), "#abcdef", "invalid updates should preserve the last palette");
assert.ok(
  logLines.some(line => line.includes("[ERROR] palette contains missing or unknown keys")),
  "invalid updates should be logged",
);

watcherCallback({ type: "error", reason: "process-exited-1" });
assert.equal([...intervalDelays.values()][0], 250, "watcher failure should restore the fast polling fallback");
poll();

unloadHandler();
assert.equal(observers[0].disconnected, true, "unload should disconnect the observer");
assert.equal(auxiliaryObserverRemoved, true, "unload should remove the auxiliary-window observer");
assert.equal(watcherUnsubscribed, true, "unload should unsubscribe from the shared watcher");
assert.equal(intervals.size, 0, "unload should clear the palette poll timer");
assert.equal(timeouts.size, 0, "unload should clear pending broadcasts and diagnostic probes");
