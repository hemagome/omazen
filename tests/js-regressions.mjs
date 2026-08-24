/* SPDX-License-Identifier: GPL-3.0-only */
/* See NOTICE for the required Omazen project attribution terms. */

import assert from "node:assert/strict";

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

globalThis.JSWindowActorChild = class {};
const prefValues = new Map();
globalThis.Services = {
  prefs: {
    getBoolPref: (name, fallback) => prefValues.get(name) ?? fallback,
    getStringPref: (name, fallback) => prefValues.get(name) ?? fallback,
  },
};

const { OmazenChild } = await import(
  new URL("../zen/Omazen/OmazenChild.sys.mjs", import.meta.url)
);

function createStyleDeclaration() {
  const values = new Map();
  return {
    removeProperty(name) {
      values.delete(name);
    },
    setProperty(name, value) {
      values.set(name, value);
    },
  };
}

const attributes = new Map();
let contentStyle = null;
let shadowStyle = null;

const shadowRoot = {
  appendChild(style) {
    shadowStyle = style;
    style.remove = () => {
      if (shadowStyle === style) shadowStyle = null;
    };
  },
  getElementById(id) {
    return shadowStyle?.id === id ? shadowStyle : null;
  },
};

const card = {
  localName: "security-privacy-card",
  nodeType: 1,
  querySelectorAll: () => [],
  shadowRoot,
};

const root = {
  localName: "html",
  nodeType: 1,
  style: createStyleDeclaration(),
  appendChild(element) {
    contentStyle = element;
  },
  querySelectorAll(selector) {
    return selector === "security-privacy-card" ? [card] : [];
  },
  removeAttribute(name) {
    attributes.delete(name);
  },
  setAttribute(name, value) {
    attributes.set(name, value);
  },
};

const document = {
  defaultView: { MutationObserver: FakeMutationObserver },
  documentElement: root,
  createElementNS() {
    return { id: "", rel: "", href: "", textContent: "" };
  },
  getElementById(id) {
    if (id === "omazen-content-style") return contentStyle;
    return null;
  },
};

const palette = {
  enabled: true,
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

const actor = new OmazenChild();
actor.document = document;
actor.receiveMessage({ name: "Omazen:Apply", data: palette });

assert.ok(shadowStyle, "enable should inject the shadow-root link style");
assert.equal(observers.length, 1, "enable should create one shadow-root observer");

actor.receiveMessage({ name: "Omazen:Apply", data: { enabled: false } });

assert.equal(shadowStyle, null, "disable should remove the injected shadow-root style");
assert.equal(observers[0].disconnected, true, "disable should disconnect the shadow-root observer");

actor.receiveMessage({ name: "Omazen:Apply", data: palette });

assert.ok(shadowStyle, "re-enable should restore the shadow-root link style");
assert.equal(observers.length, 2, "re-enable should create a fresh shadow-root observer");

actor.receiveMessage({
  name: "Omazen:Apply",
  data: { ...palette, accent: "not-a-color" },
});
assert.equal(attributes.get("data-omazen-enabled"), "true", "invalid payload should be ignored");
assert.equal(observers.length, 2, "invalid payload should not create another observer");

actor.receiveMessage({ name: "Omazen:Apply", data: { enabled: false } });
prefValues.set("omazen.enabled", true);
prefValues.set("omazen.palette.mode", palette.mode);
for (const [key, value] of Object.entries(palette)) {
  if (key !== "enabled" && key !== "mode") prefValues.set(`omazen.palette.${key}`, value);
}
actor.actorCreated();
assert.equal(attributes.get("data-omazen-enabled"), "true", "actor creation should restore saved state");
assert.ok(shadowStyle, "actor creation should restore shadow-root styles");
