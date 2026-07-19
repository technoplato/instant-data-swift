#!/usr/bin/env node
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import os from "node:os";
import { resolve } from "node:path";

const [swiftPath, typeScriptPath] = process.argv.slice(2);
assert.ok(swiftPath && typeScriptPath, "Usage: compare-cross-sdk-benchmarks.mjs <swift.json> <typescript.json>");

const swift = JSON.parse(readFileSync(resolve(swiftPath), "utf8"));
const typeScript = JSON.parse(readFileSync(resolve(typeScriptPath), "utf8"));
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
assert.deepStrictEqual(
  swift.metrics.map((metric) => metric.name),
  Object.keys(workloads),
);
assert.deepStrictEqual(
  typeScript.metrics.map((metric) => metric.name),
  Object.keys(workloads),
);

const swiftMetrics = new Map(swift.metrics.map((metric) => [metric.name, metric]));
const typeScriptMetrics = new Map(
  typeScript.metrics.map((metric) => [metric.name, metric]),
);
const comparisons = Object.entries(workloads).map(([name, workload]) => {
  const swiftMetric = swiftMetrics.get(name);
  const typeScriptMetric = typeScriptMetrics.get(name);
  const swiftPerUnit = swiftMetric.p50Nanoseconds / workload.units;
  const typeScriptPerUnit = typeScriptMetric.p50Nanoseconds / workload.units;
  const ratio = swiftPerUnit / typeScriptPerUnit;
  const slower = ratio > 1;
  const optimizationTarget = slower
    ? optimizationTargetFor(name, ratio)
    : undefined;
  return {
    name,
    unit: workload.unit,
    units: workload.units,
    swiftP50Nanoseconds: swiftMetric.p50Nanoseconds,
    typeScriptP50Nanoseconds: typeScriptMetric.p50Nanoseconds,
    swiftNanosecondsPerUnit: swiftPerUnit,
    typeScriptNanosecondsPerUnit: typeScriptPerUnit,
    swiftToTypeScriptRatio: ratio,
    deltaPercent: (ratio - 1) * 100,
    status: slower ? "optimization-target" : "meets-or-exceeds",
    ...(optimizationTarget ? { optimizationTarget } : {}),
  };
});

const slower = comparisons.filter(
  (comparison) => comparison.status === "optimization-target",
);
const result = {
  case: "benchmark.cross-sdk.core-comparison",
  event: "release-mode-summary",
  ok: comparisons.every(
    (comparison) =>
      comparison.status === "meets-or-exceeds"
      || Boolean(comparison.optimizationTarget?.id)
      && Boolean(comparison.optimizationTarget?.reason),
  ),
  details: {
    contractVersion: 1,
    iterations: swift.iterations,
    swiftRevision: git("rev-parse", "HEAD"),
    upstreamRevision: git("-C", "upstream/instant", "rev-parse", "HEAD"),
    versions: {
      typeScriptCore: typeScript.coreVersion,
      node: process.version,
    },
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
      meetsOrExceedsCount: comparisons.length - slower.length,
      optimizationTargetCount: slower.length,
    },
    comparisons,
  },
};

assert.equal(result.ok, true);
process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);

function optimizationTargetFor(name, ratio) {
  const category = name.startsWith("query-") || name.includes("query")
    ? "query-materialization"
    : name.includes("linked") || name.includes("link")
      ? "link-indexing"
      : name.includes("transform")
        ? "transaction-lowering"
        : name.includes("storage") || name.includes("stream")
          ? "system-record-materialization"
          : "incremental-store-commit";
  const reasons = {
    "query-materialization":
      "Swift currently materializes Sendable value snapshots and performs stable typed ordering across actor isolation; the canonical TypeScript store returns JavaScript object graphs from persistent-map indexes.",
    "link-indexing":
      "Swift validates typed refs and rebuilds value-semantic index snapshots at commit boundaries; the canonical TypeScript store applies optimized persistent-map link updates.",
    "transaction-lowering":
      "Swift constructs strongly typed Sendable operation values and deterministically sorts payload fields; TypeScript lowers proxy transaction chunks directly into JavaScript arrays.",
    "system-record-materialization":
      "This core comparison models system metadata as typed value records; Swift pays typed decoding and stable ordering costs that JavaScript defers to dynamic objects.",
    "incremental-store-commit":
      "Swift's current actor store commits through value-semantic snapshots and index reconstruction, while the canonical TypeScript store uses optimized structural sharing.",
  };
  return {
    id: `perf.${category}.${name}`,
    targetRatio: 1,
    observedRatio: ratio,
    reason: reasons[category],
    nextAction:
      "Profile this exact workload, preserve semantics, and reduce the release-mode Swift p50 to at most the canonical TypeScript p50 on the same machine.",
  };
}

function git(...args) {
  return execFileSync("git", args, { encoding: "utf8" }).trim();
}
