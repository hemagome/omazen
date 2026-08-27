/* SPDX-License-Identifier: GPL-3.0-only */
/* See NOTICE for the required Omazen project attribution terms. */

"use strict";

import { Subprocess } from "resource://gre/modules/Subprocess.sys.mjs";

const INOTIFYWAIT = "/usr/bin/inotifywait";
const WATCHED_LEAVES = new Set(["disabled", "palette.json"]);
const WATCHED_EVENTS = new Set(["CLOSE_WRITE", "CREATE", "DELETE", "MOVED_TO"]);
const subscribers = new Set();

let activeProcess = null;
let activeTask = null;
let activeBackend = null;
let generation = 0;

function stateDirectoryPath() {
  const configured = Services.env.get("XDG_STATE_HOME");
  const base = configured || `${Services.dirsvc.get("Home", Ci.nsIFile).path}/.local/state`;
  return `${base}/omazen`;
}

function emit(event) {
  for (const subscriber of [...subscribers]) {
    try {
      subscriber(event);
    } catch (error) {
      console.error("Omazen watcher subscriber failed", error);
    }
  }
}

export function parseWatcherLine(line) {
  const separator = line.indexOf("|");
  if (separator <= 0) return null;

  const leaf = line.slice(separator + 1).trim();
  if (!WATCHED_LEAVES.has(leaf)) return null;

  const events = line
    .slice(0, separator)
    .split(",")
    .map(event => event.trim())
    .filter(event => WATCHED_EVENTS.has(event));
  if (!events.length) return null;

  return Object.freeze({
    type: "change",
    leaf,
    events: events.join(","),
  });
}

async function readEvents(process) {
  let pending = "";

  while (true) {
    let chunk;
    try {
      chunk = await process.stdout.readString();
    } catch (error) {
      if (error?.errorCode === Subprocess.ERROR_END_OF_FILE) break;
      throw error;
    }
    if (!chunk) break;

    pending += chunk;
    let newline;
    while ((newline = pending.indexOf("\n")) >= 0) {
      const event = parseWatcherLine(pending.slice(0, newline));
      pending = pending.slice(newline + 1);
      if (event) emit(event);
    }
  }

  const event = parseWatcherLine(pending);
  if (event) emit(event);
}

function watcherFailureReason(error) {
  if (error?.errorCode === Subprocess.ERROR_BAD_EXECUTABLE) return "executable-unavailable";
  return "process-failed";
}

async function runWatcher(currentGeneration) {
  let process = null;

  try {
    process = await Subprocess.call({
      command: INOTIFYWAIT,
      arguments: [
        "--monitor",
        "--quiet",
        "--event",
        "close_write,create,delete,moved_to",
        "--format",
        "%e|%f",
        stateDirectoryPath(),
      ],
      stderr: "ignore",
    });

    if (currentGeneration !== generation || !subscribers.size) {
      await process.kill();
      return;
    }

    activeProcess = process;
    activeBackend = "inotify";
    emit(Object.freeze({ type: "ready", backend: "inotify" }));
    await readEvents(process);
    const result = await process.wait();
    if (currentGeneration === generation && subscribers.size) {
      activeBackend = null;
      emit(Object.freeze({
        type: "error",
        reason: `process-exited-${result.exitCode}`,
      }));
    }
  } catch (error) {
    if (process) await process.kill().catch(() => {});
    if (currentGeneration === generation && subscribers.size) {
      activeBackend = null;
      emit(Object.freeze({
        type: "error",
        reason: watcherFailureReason(error),
      }));
    }
  } finally {
    if (currentGeneration === generation) {
      activeProcess = null;
      activeTask = null;
      activeBackend = null;
    }
  }
}

function ensureWatcher() {
  if (activeTask || !subscribers.size) return;
  const currentGeneration = generation;
  activeTask = runWatcher(currentGeneration);
}

function stopWatcher() {
  generation += 1;
  const process = activeProcess;
  activeProcess = null;
  activeTask = null;
  activeBackend = null;
  if (process) process.kill().catch(() => {});
}

export function subscribePaletteWatcher(callback) {
  if (typeof callback !== "function") {
    throw new TypeError("watcher subscriber must be a function");
  }

  subscribers.add(callback);
  if (activeBackend) {
    callback(Object.freeze({ type: "ready", backend: activeBackend }));
  } else {
    ensureWatcher();
  }

  let subscribed = true;
  return () => {
    if (!subscribed) return;
    subscribed = false;
    subscribers.delete(callback);
    if (!subscribers.size) stopWatcher();
  };
}
