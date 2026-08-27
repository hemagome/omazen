/* SPDX-License-Identifier: GPL-3.0-only */
/* See NOTICE for the required Omazen project attribution terms. */

import assert from "node:assert/strict";
import fs from "node:fs";

const calls = [];
let readCount = 0;
const eof = Object.assign(new Error("end of file"), { errorCode: "end-of-file" });
const fakeProcess = {
  stdout: {
    async readString() {
      if (readCount++ === 0) {
        return [
          "MOVED_TO|palette.json",
          "CREATE,CLOSE_WRITE|disabled",
          "DELETE|unrelated",
          "UNKNOWN|palette.json",
          "",
        ].join("\n");
      }
      throw eof;
    },
  },
  async kill() {},
  async wait() {
    return { exitCode: 0 };
  },
};

globalThis.__omazenFakeSubprocess = {
  ERROR_BAD_EXECUTABLE: "bad-executable",
  ERROR_END_OF_FILE: "end-of-file",
  async call(options) {
    calls.push(options);
    return fakeProcess;
  },
};
globalThis.Ci = { nsIFile: {} };
globalThis.Services = {
  dirsvc: { get: () => ({ path: "/home/test" }) },
  env: { get: () => "" },
};

const source = fs
  .readFileSync(new URL("../zen/Omazen/OmazenWatcher.sys.mjs", import.meta.url), "utf8")
  .replace(
    'import { Subprocess } from "resource://gre/modules/Subprocess.sys.mjs";',
    "const Subprocess = globalThis.__omazenFakeSubprocess;",
  );
const watcherModule = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
);

assert.deepEqual(
  watcherModule.parseWatcherLine("MOVED_TO|palette.json"),
  { type: "change", leaf: "palette.json", events: "MOVED_TO" },
  "watcher should accept atomic palette replacements",
);
assert.deepEqual(
  watcherModule.parseWatcherLine("CREATE,CLOSE_WRITE|disabled"),
  { type: "change", leaf: "disabled", events: "CREATE,CLOSE_WRITE" },
  "watcher should accept disabled marker changes",
);
assert.equal(
  watcherModule.parseWatcherLine("MOVED_TO|unrelated"),
  null,
  "watcher should ignore unrelated state files",
);
assert.equal(
  watcherModule.parseWatcherLine("UNKNOWN|palette.json"),
  null,
  "watcher should ignore unknown event names",
);

const firstEvents = [];
const secondEvents = [];
const lateEvents = [];
let unsubscribeLate = () => {};
let finish;
const finished = new Promise(resolve => {
  finish = resolve;
});
const unsubscribeFirst = watcherModule.subscribePaletteWatcher(event => {
  firstEvents.push(event);
  if (event.type === "ready") {
    unsubscribeLate = watcherModule.subscribePaletteWatcher(lateEvent => {
      lateEvents.push(lateEvent);
    });
  }
  if (event.type === "error") finish();
});
const unsubscribeSecond = watcherModule.subscribePaletteWatcher(event => {
  secondEvents.push(event);
});

await finished;

assert.equal(calls.length, 1, "watcher should share one inotify process across subscribers");
assert.equal(calls[0].command, "/usr/bin/inotifywait", "watcher should execute the fixed binary path");
assert.deepEqual(
  firstEvents.map(event => event.type),
  ["ready", "change", "change", "error"],
  "watcher should publish readiness, relevant changes and process failure",
);
assert.deepEqual(
  secondEvents.map(event => event.type),
  ["ready", "change", "change", "error"],
  "all subscribers should receive the same watcher events",
);
assert.deepEqual(
  lateEvents.map(event => event.type),
  ["ready", "change", "change", "error"],
  "a window subscribing after startup should immediately learn that the shared watcher is ready",
);

unsubscribeFirst();
unsubscribeSecond();
unsubscribeLate();
