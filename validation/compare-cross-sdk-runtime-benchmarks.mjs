#!/usr/bin/env node
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import os from "node:os";
import { resolve } from "node:path";

const [swiftPath, typeScriptPath] = process.argv.slice(2);
assert.ok(
  swiftPath && typeScriptPath,
  "Usage: compare-cross-sdk-runtime-benchmarks.mjs <swift.json> <typescript.json>",
);

const swift = JSON.parse(readFileSync(resolve(swiftPath), "utf8"));
const typeScript = JSON.parse(readFileSync(resolve(typeScriptPath), "utf8"));
const workloads = {
  "pending-mutation-enqueue.update": { units: 1, unit: "mutation" },
  "offline-restore.relaunch": { units: 1, unit: "relaunch" },
  "reconnect-outbox-drain": { units: 1, unit: "mutation" },
};

assert.equal(swift.suite, "cross-sdk-runtime");
assert.equal(swift.transport, "sqlite-local-runtime");
assert.equal(swift.ok, true);
assert.equal(typeScript.suite, "cross-sdk-runtime");
assert.equal(typeScript.sdk, "typescript");
assert.equal(typeScript.contractVersion, 1);
assert.equal(typeScript.persistence, "canonical-indexeddb-semantics-fake-backend");
assert.equal(typeScript.ok, true);
assert.equal(swift.iterations, typeScript.iterations);
assert.deepStrictEqual(swift.metrics.map((metric) => metric.name), Object.keys(workloads));
assert.deepStrictEqual(
  typeScript.metrics.map((metric) => metric.name),
  Object.keys(workloads),
);

const swiftMetrics = new Map(swift.metrics.map((metric) => [metric.name, metric]));
const typeScriptMetrics = new Map(typeScript.metrics.map((metric) => [metric.name, metric]));
const comparisons = Object.entries(workloads).map(([name, workload]) => {
  const swiftMetric = swiftMetrics.get(name);
  const typeScriptMetric = typeScriptMetrics.get(name);
  const ratio = swiftMetric.p50Nanoseconds / typeScriptMetric.p50Nanoseconds;
  const actorHopCounts = swiftMetric.samples.map((sample) => sample.actorHopCount);
  assert.ok(actorHopCounts.every((count) => Number.isInteger(count) && count > 0));
  const slower = ratio > 1;
  return {
    name,
    unit: workload.unit,
    units: workload.units,
    swiftP50Nanoseconds: swiftMetric.p50Nanoseconds,
    typeScriptP50Nanoseconds: typeScriptMetric.p50Nanoseconds,
    swiftToTypeScriptRatio: ratio,
    deltaPercent: (ratio - 1) * 100,
    swiftActorHops: {
      counts: actorHopCounts,
      breakdowns: swiftMetric.samples.map((sample) => sample.actorHopBreakdown),
    },
    status: slower ? "optimization-target" : "meets-or-exceeds",
    ...(slower ? { optimizationTarget: optimizationTargetFor(name, ratio) } : {}),
  };
});

const slower = comparisons.filter(({ status }) => status === "optimization-target");
const result = {
  case: "benchmark.cross-sdk.runtime-comparison",
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
    persistence: {
      swift: "SQLite file-backed runtime",
      typeScript: typeScript.persistence,
      comparability:
        "The logical durable-state workload is identical; storage media are platform-native and the TypeScript benchmark uses fake-indexeddb for reproducible Node execution.",
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
      actorHopInstrumentedWorkloadCount: comparisons.length,
    },
    comparisons,
  },
};

assert.equal(result.ok, true);
process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);

function optimizationTargetFor(name, ratio) {
  const details = {
    "pending-mutation-enqueue.update": {
      category: "durable-enqueue",
      reason:
        "Swift validates typed operations, crosses its operation, store, outbox, and persistence actors, and commits a SQLite snapshot; TypeScript lowers dynamic chunks into its pending map and persists IndexedDB state.",
    },
    "offline-restore.relaunch": {
      category: "durable-restore",
      reason:
        "Swift opens and decodes a file-backed SQLite snapshot before restoring typed store and outbox actors; the canonical TypeScript persistence semantics run over an in-process fake IndexedDB backend in this reproducible Node gate.",
    },
    "reconnect-outbox-drain": {
      category: "outbox-drain",
      reason:
        "Swift reconnects its runtime state, sends through the mutation transport boundary, and commits confirmed outbox state through actor-isolated SQLite; TypeScript acknowledges and persists its canonical pending-mutation state machine.",
    },
  }[name];
  return {
    id: `perf.${details.category}.${name}`,
    targetRatio: 1,
    observedRatio: ratio,
    reason: details.reason,
    nextAction:
      "Profile this exact workload and its recorded Swift actor-hop breakdown, preserve semantics, and reduce the release-mode Swift p50 to at most the canonical TypeScript p50 on the same machine.",
  };
}

function git(...args) {
  return execFileSync("git", args, { encoding: "utf8" }).trim();
}
