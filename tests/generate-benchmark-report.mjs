#!/usr/bin/env node
// SPDX-License-Identifier: GPL-3.0-only
// See NOTICE for the required Omazen project attribution terms.

import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const outputDir = process.argv[2];
if (!outputDir) {
  process.stderr.write("Usage: tests/generate-benchmark-report.mjs OUTPUT_DIR\n");
  process.exit(2);
}

function parseCsv(text) {
  const [header, ...lines] = text.trim().split("\n");
  const keys = header.split(",");
  return lines.filter(Boolean).map((line) => {
    const values = line.split(",");
    return Object.fromEntries(keys.map((key, index) => [key, values[index] ?? ""]));
  });
}

function percentile(sorted, fraction) {
  if (sorted.length === 0) return null;
  const position = (sorted.length - 1) * fraction;
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  if (lower === upper) return sorted[lower];
  return sorted[lower] + (position - lower) * (sorted[upper] - sorted[lower]);
}

function summarize(values) {
  const sorted = values.map(Number).filter(Number.isFinite).sort((a, b) => a - b);
  if (sorted.length === 0) return null;
  const mean = sorted.reduce((sum, value) => sum + value, 0) / sorted.length;
  const variance = sorted.reduce((sum, value) => sum + (value - mean) ** 2, 0) / sorted.length;
  return {
    n: sorted.length,
    min: sorted[0],
    p50: percentile(sorted, 0.5),
    mean,
    stddev: Math.sqrt(variance),
    p95: percentile(sorted, 0.95),
    p99: percentile(sorted, 0.99),
    max: sorted.at(-1),
  };
}

function milliseconds(value) {
  return (value / 1_000_000).toFixed(3);
}

function mebibytes(value) {
  return (value / 1024 / 1024).toFixed(3);
}

const latency = parseCsv(await readFile(path.join(outputDir, "latency.csv"), "utf8"));
const cpu = parseCsv(await readFile(path.join(outputDir, "cpu.csv"), "utf8"));
const memory = parseCsv(await readFile(path.join(outputDir, "memory.csv"), "utf8"));
const successful = latency.filter((row) => row.outcome === "ok");
const successfulKeys = new Set(successful.map((row) => `${row.scenario}/${row.run}/${row.iteration}`));
const isSuccessful = (row) => successfulKeys.has(`${row.scenario}/${row.run}/${row.iteration}`);
const wall = summarize(successful.map((row) => row.wall_ns));
const successfulCpu = cpu.filter(isSuccessful);
const successfulMemory = memory.filter(isSuccessful);
const userCpu = summarize(successfulCpu.map((row) => row.user_cpu_ns));
const systemCpu = summarize(successfulCpu.map((row) => row.system_cpu_ns));
const rss = summarize(successfulMemory.map((row) => row.max_process_tree_rss_bytes).filter((value) => Number(value) > 0));
const pss = summarize(successfulMemory.map((row) => row.max_process_tree_pss_bytes).filter((value) => Number(value) > 0));
const warnings = latency.filter((row) => row.warnings !== "");

const rows = [
  ["Wall latency", wall, milliseconds, "ms"],
  ["User CPU", userCpu, milliseconds, "ms"],
  ["System CPU", systemCpu, milliseconds, "ms"],
  ["Process-tree RSS", rss, mebibytes, "MiB"],
  ["Process-tree PSS", pss, mebibytes, "MiB"],
];

let report = "# Generated benchmark summary\n\n";
report += "This file is generated entirely from `latency.csv`, `cpu.csv`, and `memory.csv`. Failed samples and sampler warnings remain in the raw files.\n\n";
report += `Successful samples: ${successful.length}/${latency.length}. Sampler warnings: ${warnings.length}.\n\n`;
report += "| Metric | N | Minimum | p50 | Mean | Std. dev. | p95 | p99 | Maximum | Unit |\n";
report += "|---|---:|---:|---:|---:|---:|---:|---:|---:|---|\n";
for (const [label, summary, formatter, unit] of rows) {
  if (!summary) continue;
  report += `| ${label} | ${summary.n} | ${formatter(summary.min)} | ${formatter(summary.p50)} | ${formatter(summary.mean)} | ${formatter(summary.stddev)} | ${formatter(summary.p95)} | ${formatter(summary.p99)} | ${formatter(summary.max)} | ${unit} |\n`;
}
report += "\nPercentiles use linear interpolation at `(N - 1) × p`. No outlier is removed.\n";

await writeFile(path.join(outputDir, "summary.md"), report);
