/* SPDX-License-Identifier: GPL-3.0-only */
/* See NOTICE for the required Omazen project attribution terms. */

"use strict";

import {
  COLOR_KEYS,
  setRootPalette,
  validatePayload,
} from "./OmazenPalette.sys.mjs";

const STYLE_ID = "omazen-content-style";
const SHADOW_LINK_STYLE_ID = "omazen-shadow-link-style";
const STYLE_URI = "chrome://userscripts/content/Omazen/omazen-content-v1.5.0.css";
const shadowObservers = new WeakMap();

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

function visitSecurityPrivacyCards(node, callback) {
  if (node?.nodeType !== 1) return;
  if (node.localName === "security-privacy-card") callback(node);
  for (const card of node.querySelectorAll?.("security-privacy-card") || []) callback(card);
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

  visitSecurityPrivacyCards(document.documentElement, applyToCard);
  if (shadowObservers.has(document)) return;
  const observer = new document.defaultView.MutationObserver(records => {
    for (const record of records) {
      for (const node of record.addedNodes) visitSecurityPrivacyCards(node, applyToCard);
    }
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });
  shadowObservers.set(document, observer);
}

function removeSecurityPrivacyCardLinks(document) {
  shadowObservers.get(document)?.disconnect();
  shadowObservers.delete(document);
  visitSecurityPrivacyCards(document.documentElement, card => {
    card.shadowRoot?.getElementById(SHADOW_LINK_STYLE_ID)?.remove();
  });
}

function applyToDocument(document, payload) {
  const root = document?.documentElement;
  if (!root) return;
  ensureStyle(document);
  const acceptButton = document.getElementById("commonDialog")?.getButton?.("accept");
  if (!setRootPalette(root, payload, payload.enabled)) {
    removeSecurityPrivacyCardLinks(document);
    acceptButton?.part.remove("omazen-primary-button");
    return;
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
