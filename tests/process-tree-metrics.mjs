#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-only
// See NOTICE for the required Omazen project attribution terms.

import { spawn, spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import process from "node:process";

function usage() {
  process.stderr.write("Usage: tests/process-tree-metrics.mjs -- command [arguments...]\n");
}

const separator = process.argv.indexOf("--");
if (separator < 0 || separator === process.argv.length - 1) {
  usage();
  process.exit(2);
}

const [command, ...args] = process.argv.slice(separator + 1);
const clockResult = spawnSync("getconf", ["CLK_TCK"], { encoding: "utf8" });
const clockTicks = Number.parseInt(clockResult.stdout, 10) || 100;
const pageSizeResult = spawnSync("getconf", ["PAGESIZE"], { encoding: "utf8" });
const pageSize = Number.parseInt(pageSizeResult.stdout, 10) || 4096;
const started = process.hrtime.bigint();
const child = spawn(command, args, {
  env: process.env,
  stdio: ["ignore", "ignore", "ignore"],
});

const seen = new Map();
let maxAggregateRssBytes = 0;
let maxAggregatePssBytes = 0;
let maxProcessCount = 0;
let sampleCount = 0;
let sampling = false;

async function processSnapshot(pid) {
  const statText = await readFile(`/proc/${pid}/stat`, "utf8");
  const end = statText.lastIndexOf(")");
  const fields = statText.slice(end + 2).trim().split(/\s+/);
  const userTicks = Number.parseInt(fields[11], 10) || 0;
  const systemTicks = Number.parseInt(fields[12], 10) || 0;
  const rssPages = Number.parseInt(fields[21], 10) || 0;
  let rssBytes = rssPages * pageSize;
  let pssBytes = 0;
  try {
    const rollup = await readFile(`/proc/${pid}/smaps_rollup`, "utf8");
    const rss = /^Rss:\s+(\d+) kB$/m.exec(rollup);
    const pss = /^Pss:\s+(\d+) kB$/m.exec(rollup);
    if (rss) rssBytes = Number.parseInt(rss[1], 10) * 1024;
    if (pss) pssBytes = Number.parseInt(pss[1], 10) * 1024;
  } catch {
    // A short-lived process can exit between the stat and rollup reads.
  }
  let children = [];
  try {
    const childText = await readFile(`/proc/${pid}/task/${pid}/children`, "utf8");
    children = childText.trim() === "" ? [] : childText.trim().split(/\s+/).map(Number);
  } catch {
    // The process exited while it was sampled.
  }
  return { pid, userTicks, systemTicks, rssBytes, pssBytes, children };
}

async function sampleTree() {
  if (sampling) return;
  sampling = true;
  try {
    const pending = [child.pid];
    const current = [];
    const visited = new Set();
    while (pending.length > 0) {
      const pid = pending.shift();
      if (!Number.isInteger(pid) || visited.has(pid)) continue;
      visited.add(pid);
      try {
        const snapshot = await processSnapshot(pid);
        current.push(snapshot);
        pending.push(...snapshot.children);
      } catch {
        // Expected for processes shorter than the sampling interval.
      }
    }
    let aggregateRss = 0;
    let aggregatePss = 0;
    for (const snapshot of current) {
      aggregateRss += snapshot.rssBytes;
      aggregatePss += snapshot.pssBytes;
      const previous = seen.get(snapshot.pid);
      if (!previous || snapshot.userTicks + snapshot.systemTicks > previous.userTicks + previous.systemTicks) {
        seen.set(snapshot.pid, snapshot);
      }
    }
    maxAggregateRssBytes = Math.max(maxAggregateRssBytes, aggregateRss);
    maxAggregatePssBytes = Math.max(maxAggregatePssBytes, aggregatePss);
    maxProcessCount = Math.max(maxProcessCount, current.length);
    sampleCount += 1;
  } finally {
    sampling = false;
  }
}

await sampleTree();
const interval = setInterval(sampleTree, 1);
const result = await new Promise((resolve) => {
  child.once("error", (error) => resolve({ error, code: null, signal: null }));
  child.once("exit", (code, signal) => resolve({ error: null, code, signal }));
});
const ended = process.hrtime.bigint();
clearInterval(interval);
await sampleTree();

let userTicks = 0;
let systemTicks = 0;
for (const snapshot of seen.values()) {
  userTicks += snapshot.userTicks;
  systemTicks += snapshot.systemTicks;
}

const report = {
  schema_version: 1,
  command,
  arguments: args,
  exit_code: result.code,
  signal: result.signal,
  spawn_error: result.error?.message ?? null,
  wall_ns: Number(ended - started),
  user_cpu_ns: Math.round((userTicks * 1_000_000_000) / clockTicks),
  system_cpu_ns: Math.round((systemTicks * 1_000_000_000) / clockTicks),
  max_process_tree_rss_bytes: maxAggregateRssBytes,
  max_process_tree_pss_bytes: maxAggregatePssBytes,
  observed_processes: seen.size,
  max_concurrent_processes: maxProcessCount,
  samples: sampleCount,
  warnings: sampleCount < 2 ? ["process tree completed before two samples were captured"] : [],
};

process.stdout.write(`${JSON.stringify(report)}\n`);
if (result.error) process.exit(127);
process.exit(result.code ?? 128);
