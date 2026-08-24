"use strict";

const STYLE_ID = "omazen-content-style";
const SHADOW_LINK_STYLE_ID = "omazen-shadow-link-style";
const STYLE_URI = "chrome://userscripts/content/Omazen/omazen-content-v1.0.0.css";
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
const shadowObservers = new WeakMap();

function validatePayload(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  if (value.enabled === false) return { enabled: false };
  if (value.enabled !== true || (value.mode !== "dark" && value.mode !== "light")) return null;
  const palette = { enabled: true, mode: value.mode };
  for (const key of COLOR_KEYS) {
    if (typeof value[key] !== "string" || !COLOR_RE.test(value[key])) return null;
    palette[key] = value[key].toLowerCase();
  }
  return palette;
}

function readPrefs() {
  if (!Services.prefs.getBoolPref("omazen.enabled", false)) return { enabled: false };
  const payload = {
    enabled: true,
    mode: Services.prefs.getStringPref("omazen.palette.mode", ""),
  };
  for (const key of COLOR_KEYS) {
    payload[key] = Services.prefs.getStringPref(`omazen.palette.${key}`, "");
  }
  return validatePayload(payload) || { enabled: false };
}

function ensureStyle(document) {
  let link = document.getElementById(STYLE_ID);
  if (link) return link;
  link = document.createElementNS("http://www.w3.org/1999/xhtml", "link");
  link.id = STYLE_ID;
  link.rel = "stylesheet";
  link.href = STYLE_URI;
  document.documentElement.appendChild(link);
  return link;
}

function ensureSecurityPrivacyCardLinks(document) {
  const applyToCard = card => {
    const shadowRoot = card.shadowRoot;
    if (!shadowRoot || shadowRoot.getElementById(SHADOW_LINK_STYLE_ID)) return;
    const style = document.createElementNS("http://www.w3.org/1999/xhtml", "style");
    style.id = SHADOW_LINK_STYLE_ID;
    style.textContent = `
      a {
        color: var(--omazen-accent, inherit) !important;
      }
      a:hover,
      a:hover:active {
        color: color-mix(in srgb, var(--omazen-accent, currentColor) 82%, var(--omazen-foreground, currentColor)) !important;
      }
    `;
    shadowRoot.appendChild(style);
  };

  const scan = node => {
    if (node?.nodeType !== 1) return;
    if (node.localName === "security-privacy-card") applyToCard(node);
    for (const card of node.querySelectorAll?.("security-privacy-card") || []) applyToCard(card);
  };

  scan(document.documentElement);
  if (shadowObservers.has(document)) return;
  const observer = new document.defaultView.MutationObserver(records => {
    for (const record of records) {
      for (const node of record.addedNodes) scan(node);
    }
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  shadowObservers.set(document, observer);
}

function applyToDocument(document, payload) {
  const root = document?.documentElement;
  if (!root) return;
  ensureStyle(document);
  const acceptButton = document.getElementById("commonDialog")?.getButton?.("accept");
  if (!payload.enabled) {
    root.removeAttribute("data-omazen-enabled");
    root.removeAttribute("data-omazen-mode");
    root.style.removeProperty("color-scheme");
    for (const key of COLOR_KEYS) {
      root.style.removeProperty(`--omazen-${key.replaceAll("_", "-")}`);
    }
    acceptButton?.part.remove("omazen-primary-button");
    return;
  }
  root.setAttribute("data-omazen-enabled", "true");
  root.setAttribute("data-omazen-mode", payload.mode);
  root.style.setProperty("color-scheme", payload.mode);
  for (const key of COLOR_KEYS) {
    root.style.setProperty(`--omazen-${key.replaceAll("_", "-")}`, payload[key]);
  }
  ensureSecurityPrivacyCardLinks(document);
  acceptButton?.part.add("omazen-primary-button");
}

export class OmazenChild extends JSWindowActorChild {
  actorCreated() {
    applyToDocument(this.document, readPrefs());
  }

  handleEvent(event) {
    if (event.type === "DOMContentLoaded") applyToDocument(this.document, readPrefs());
  }

  receiveMessage(message) {
    if (message?.name !== "Omazen:Apply") return null;
    const payload = validatePayload(message.data);
    if (payload) applyToDocument(this.document, payload);
    return null;
  }
}
