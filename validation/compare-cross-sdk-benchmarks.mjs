#!/usr/bin/env node
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import os from "node:os";
import { resolve } from "node:path";

const [swiftPath, typeScriptPath] = process.argv.slice(2);
assert.ok(
  swiftPath && typeScriptPath,
  "Usage: compare-cross-sdk-benchmarks.mjs <swift.json> <typescript.json>",
);

const swift = JSON.parse(readFileSync(resolve(swiftPath), "utf8"));
const typeScript = JSON.parse(readFileSync(resolve(typeScriptPath), "utf8"));
const maxP50Ratio = positiveNumber("INSTANT_SWIFT_DATA_MAX_P50_RATIO", 1);
const maxP95Ratio = positiveNumber("INSTANT_SWIFT_DATA_MAX_P95_RATIO", 1);

const workloads = {
  "transaction-transform.scalar": { units: 1_000, unit: "entity" },
  "triple-insert.todos": { units: 1_000, unit: "entity" },
  "triple-update.todos": { units: 1_000, unit: "entity" },
  "triple-retract.todos": { units: 1_000, unit: "entity" },
  "query-materialization.flat": { units: 1_000, unit: "entity" },
  "query-materialization.nested": { units: 1_000, unit: "entity" },
  "query-materialization.reverse": { units: 100, unit: "parent" },
  "high-bandwidth.scalar-updates": { units: 10_000, unit: "update" },
  "high-bandwidth.linked-writes": { units: 1_000, unit: "link" },
  "storage-metadata.query": { units: 100, unit: "record" },
  "stream-write.chunks": { units: 1_000, unit: "chunk" },
  "stream-read.chunks": { units: 1_000, unit: "chunk" },
};

assert.equal(swift.suite, "cross-sdk-core");
assert.equal(swift.transport, "in-memory-core");
assert.equal(swift.ok, true);
assert.equal(typeScript.suite, "cross-sdk-core");
assert.equal(typeScript.sdk, "typescript");
assert.equal(typeScript.contractVersion, 1);
assert.equal(typeScript.ok, true);
assert.equal(swift.iterations, typeScript.iterations);
assert.deepStrictEqual(swift.metrics.map(({ name }) => name), Object.keys(workloads));
assert.deepStrictEqual(typeScript.metrics.map(({ name }) => name), Object.keys(workloads));

const swiftMetrics = new Map(swift.metrics.map((metric) => [metric.name, metric]));
const typeScriptMetrics = new Map(typeScript.metrics.map((metric) => [metric.name, metric]));
const comparisons = Object.entries(workloads).map(([name, workload]) => {
  const swiftMetric = swiftMetrics.get(name);
  const typeScriptMetric = typeScriptMetrics.get(name);
  assert.ok(swiftMetric && typeScriptMetric, `Missing benchmark metric ${name}`);

  const p50Ratio = ratio(swiftMetric.p50Nanoseconds, typeScriptMetric.p50Nanoseconds);
  const p95Ratio = ratio(swiftMetric.p95Nanoseconds, typeScriptMetric.p95Nanoseconds);
  const resultCountParity = sampleFieldParity(swiftMetric, typeScriptMetric, "resultCount");
  const explicitHashParity = optionalHashParity(swiftMetric, typeScriptMetric);
  const correctnessPass = resultCountParity && explicitHashParity;
  const performancePass = p50Ratio <= maxP50Ratio && p95Ratio <= maxP95Ratio;
  const pass = correctnessPass && performancePass;

  return {
    name,
    unit: workload.unit,
    units: workload.units,
    swiftP50Nanoseconds: swiftMetric.p50Nanoseconds,
    typeScriptP50Nanoseconds: typeScriptMetric.p50Nanoseconds,
    swiftP95Nanoseconds: swiftMetric.p95Nanoseconds,
    typeScriptP95Nanoseconds: typeScriptMetric.p95Nanoseconds,
    swiftNanosecondsPerUnit: swiftMetric.p50Nanoseconds / workload.units,
    typeScriptNanosecondsPerUnit: typeScriptMetric.p50Nanoseconds / workload.units,
    swiftToTypeScriptP50Ratio: p50Ratio,
    swiftToTypeScriptP95Ratio: p95Ratio,
    limits: { maxP50Ratio, maxP95Ratio },
    correctness: {
      resultCountParity,
      explicitHashParity,
      evidence: "SDK-internal assertions plus cross-SDK result-count parity; explicit hashes are compared when emitted",
    },
    status: pass ? "pass" : "fail",
    failures: [
      ...(p50Ratio > maxP50Ratio
        ? [`p50 ratio ${p50Ratio.toFixed(3)} exceeds ${maxP50Ratio}`]
        : []),
      ...(p95Ratio > maxP95Ratio
        ? [`p95 ratio ${p95Ratio.toFixed(3)} exceeds ${maxP95Ratio}`]
        : []),
      ...(!resultCountParity ? ["result-count samples differ"] : []),
      ...(!explicitHashParity ? ["correctness hashes differ"] : []),
    ],
  };
});

const failures = comparisons.filter(({ status }) => status === "fail");
const result = {
  case: "benchmark.cross-sdk.core-comparison",
  event: "release-mode-summary",
  ok: failures.length === 0,
  policy: {
    failClosed: true,
    maxP50Ratio,
    maxP95Ratio,
    note: "An optimization explanation never converts a failed metric into a pass.",
  },
  details: {
    contractVersion: 2,
    iterations: swift.iterations,
    swiftRevision: git("rev-parse", "HEAD"),
    upstreamRevision: git("-C", "upstream/instant", "rev-parse", "HEAD"),
    versions: { typeScriptCore: typeScript.coreVersion, node: process.version },
    environment: {
      platform: os.platform(),
      release: os.release(),
      architecture: os.arch(),
      cpuModel: os.cpus()[0]?.model ?? "unknown",
      cpuCount: os.cpus().length,
      totalMemoryBytes: os.totalmem(),
    },
    summary: {
      workloadCount: comparisons.length,
      passCount: comparisons.length - failures.length,
      failureCount: failures.length,
    },
    comparisons,
  },
};

process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
if (!result.ok) process.exitCode = 1;

function ratio(numerator, denominator) {
  assert.ok(Number.isFinite(numerator) && numerator >= 0, "Invalid Swift duration");
  assert.ok(Number.isFinite(denominator) && denominator > 0, "Invalid TypeScript duration");
  return numerator / denominator;
}

function sampleFieldParity(a, b, field) {
  const left = a.samples.map((sample) => sample[field] ?? null);
  const right = b.samples.map((sample) => sample[field] ?? null);
  if (left.every((value) => value === null) && right.every((value) => value === null)) {
    return true;
  }
  return JSON.stringify(left) === JSON.stringify(right);
}

function optionalHashParity(a, b) {
  const left = a.correctnessHash ?? null;
  const right = b.correctnessHash ?? null;
  return left === null && right === null ? true : left === right;
}

function positiveNumber(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const value = Number(raw);
  assert.ok(Number.isFinite(value) && value > 0, `${name} must be a positive number`);
  return value;
}

function git(...args) {
  return execFileSync("git", args, { encoding: "utf8" }).trim();
}
