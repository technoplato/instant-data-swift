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
const maxP50Ratio = positiveNumber(
  "INSTANT_SWIFT_DATA_MAX_RUNTIME_P50_RATIO",
  positiveNumber("INSTANT_SWIFT_DATA_MAX_P50_RATIO", 1),
);
const maxP95Ratio = positiveNumber(
  "INSTANT_SWIFT_DATA_MAX_RUNTIME_P95_RATIO",
  positiveNumber("INSTANT_SWIFT_DATA_MAX_P95_RATIO", 1),
);

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
assert.deepStrictEqual(swift.metrics.map(({ name }) => name), Object.keys(workloads));
assert.deepStrictEqual(typeScript.metrics.map(({ name }) => name), Object.keys(workloads));

const swiftMetrics = new Map(swift.metrics.map((metric) => [metric.name, metric]));
const typeScriptMetrics = new Map(typeScript.metrics.map((metric) => [metric.name, metric]));
const comparisons = Object.entries(workloads).map(([name, workload]) => {
  const swiftMetric = swiftMetrics.get(name);
  const typeScriptMetric = typeScriptMetrics.get(name);
  assert.ok(swiftMetric && typeScriptMetric, `Missing benchmark metric ${name}`);

  const actorHopCounts = swiftMetric.samples.map((sample) => sample.actorHopCount);
  const actorHopInstrumentationValid = actorHopCounts.every(
    (count) => Number.isInteger(count) && count > 0,
  );
  const p50Ratio = ratio(swiftMetric.p50Nanoseconds, typeScriptMetric.p50Nanoseconds);
  const p95Ratio = ratio(swiftMetric.p95Nanoseconds, typeScriptMetric.p95Nanoseconds);
  const pendingCountParity = sampleFieldParity(
    swiftMetric,
    typeScriptMetric,
    "pendingMutationCount",
  );
  const resultCountParity = sampleFieldParity(swiftMetric, typeScriptMetric, "resultCount");
  const correctnessPass =
    actorHopInstrumentationValid && pendingCountParity && resultCountParity;
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
    swiftToTypeScriptP50Ratio: p50Ratio,
    swiftToTypeScriptP95Ratio: p95Ratio,
    limits: { maxP50Ratio, maxP95Ratio },
    swiftActorHops: {
      valid: actorHopInstrumentationValid,
      counts: actorHopCounts,
      breakdowns: swiftMetric.samples.map((sample) => sample.actorHopBreakdown),
    },
    correctness: {
      pendingCountParity,
      resultCountParity,
      evidence: "durable pending-count/result-count parity plus Swift actor-hop instrumentation",
    },
    status: pass ? "pass" : "fail",
    failures: [
      ...(p50Ratio > maxP50Ratio
        ? [`p50 ratio ${p50Ratio.toFixed(3)} exceeds ${maxP50Ratio}`]
        : []),
      ...(p95Ratio > maxP95Ratio
        ? [`p95 ratio ${p95Ratio.toFixed(3)} exceeds ${maxP95Ratio}`]
        : []),
      ...(!pendingCountParity ? ["pending-mutation counts differ"] : []),
      ...(!resultCountParity ? ["result counts differ"] : []),
      ...(!actorHopInstrumentationValid ? ["Swift actor-hop evidence is missing"] : []),
    ],
  };
});

const failures = comparisons.filter(({ status }) => status === "fail");
const result = {
  case: "benchmark.cross-sdk.runtime-comparison",
  event: "release-mode-summary",
  ok: failures.length === 0,
  policy: {
    failClosed: true,
    maxP50Ratio,
    maxP95Ratio,
    note: "Durability or latency regressions block publication; explanations are diagnostic only.",
  },
  details: {
    contractVersion: 2,
    iterations: swift.iterations,
    swiftRevision: git("rev-parse", "HEAD"),
    upstreamRevision: git("-C", "upstream/instant", "rev-parse", "HEAD"),
    versions: { typeScriptCore: typeScript.coreVersion, node: process.version },
    persistence: {
      swift: "SQLite file-backed runtime",
      typeScript: typeScript.persistence,
      comparability:
        "The logical durable-state chronology is identical; storage engines remain platform-native.",
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
      passCount: comparisons.length - failures.length,
      failureCount: failures.length,
      actorHopInstrumentedWorkloadCount: comparisons.filter(
        ({ swiftActorHops }) => swiftActorHops.valid,
      ).length,
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
