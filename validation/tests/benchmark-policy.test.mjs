#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const root = resolve(import.meta.dirname, "../..");
const coreComparator = resolve(root, "validation/compare-cross-sdk-benchmarks.mjs");
const runtimeComparator = resolve(
  root,
  "validation/compare-cross-sdk-runtime-benchmarks.mjs",
);
const coreNames = [
  "transaction-transform.scalar",
  "triple-insert.todos",
  "triple-update.todos",
  "triple-retract.todos",
  "query-materialization.flat",
  "query-materialization.nested",
  "query-materialization.reverse",
  "high-bandwidth.scalar-updates",
  "high-bandwidth.linked-writes",
  "storage-metadata.query",
  "stream-write.chunks",
  "stream-read.chunks",
];
const runtimeNames = [
  "pending-mutation-enqueue.update",
  "offline-restore.relaunch",
  "reconnect-outbox-drain",
];

function metric(name, duration, extra = {}) {
  return {
    name,
    p50Nanoseconds: duration,
    p95Nanoseconds: duration,
    samples: [{ iteration: 0, durationNanoseconds: duration, ...extra }],
  };
}

function run(comparator, swift, typeScript, env = {}) {
  const directory = mkdtempSync(join(tmpdir(), "instant-benchmark-policy-"));
  try {
    const swiftPath = join(directory, "swift.json");
    const typeScriptPath = join(directory, "typescript.json");
    writeFileSync(swiftPath, JSON.stringify(swift));
    writeFileSync(typeScriptPath, JSON.stringify(typeScript));
    const result = spawnSync(
      process.execPath,
      [comparator, swiftPath, typeScriptPath],
      {
        cwd: root,
        env: { ...process.env, ...env },
        encoding: "utf8",
      },
    );
    return {
      status: result.status,
      stdout: result.stdout,
      stderr: result.stderr,
      json: result.stdout ? JSON.parse(result.stdout) : null,
    };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function coreFixture(swiftDuration, typeScriptDuration) {
  return {
    swift: {
      suite: "cross-sdk-core",
      transport: "in-memory-core",
      ok: true,
      iterations: 1,
      metrics: coreNames.map((name) => metric(name, swiftDuration, { resultCount: 1 })),
    },
    typeScript: {
      suite: "cross-sdk-core",
      sdk: "typescript",
      contractVersion: 1,
      coreVersion: "test",
      ok: true,
      iterations: 1,
      metrics: coreNames.map((name) =>
        metric(name, typeScriptDuration, { resultCount: 1 }),
      ),
    },
  };
}

function runtimeFixture(swiftDuration, typeScriptDuration) {
  return {
    swift: {
      suite: "cross-sdk-runtime",
      transport: "sqlite-local-runtime",
      ok: true,
      iterations: 1,
      metrics: runtimeNames.map((name, index) =>
        metric(name, swiftDuration, {
          pendingMutationCount: index === 2 ? 0 : 1,
          resultCount: index === 0 ? undefined : 1,
          actorHopCount: 1,
          actorHopBreakdown: { benchmark: 1 },
        }),
      ),
    },
    typeScript: {
      suite: "cross-sdk-runtime",
      sdk: "typescript",
      contractVersion: 1,
      coreVersion: "test",
      persistence: "canonical-indexeddb-semantics-fake-backend",
      ok: true,
      iterations: 1,
      metrics: runtimeNames.map((name, index) =>
        metric(name, typeScriptDuration, {
          pendingMutationCount: index === 2 ? 0 : 1,
          resultCount: index === 0 ? undefined : 1,
        }),
      ),
    },
  };
}

test("core comparator passes equal performance and correctness", () => {
  const fixtures = coreFixture(100, 100);
  const result = run(coreComparator, fixtures.swift, fixtures.typeScript);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.json.ok, true);
  assert.equal(result.json.details.summary.failureCount, 0);
});

test("core comparator exits nonzero when Swift is slower", () => {
  const fixtures = coreFixture(101, 100);
  const result = run(coreComparator, fixtures.swift, fixtures.typeScript);
  assert.equal(result.status, 1);
  assert.equal(result.json.ok, false);
  assert.equal(result.json.details.summary.failureCount, coreNames.length);
});

test("core comparator exits nonzero on correctness drift", () => {
  const fixtures = coreFixture(100, 100);
  fixtures.swift.metrics[0].samples[0].resultCount = 2;
  const result = run(coreComparator, fixtures.swift, fixtures.typeScript);
  assert.equal(result.status, 1);
  assert.equal(result.json.details.comparisons[0].correctness.resultCountParity, false);
});

test("runtime comparator passes equal durable chronology", () => {
  const fixtures = runtimeFixture(100, 100);
  const result = run(runtimeComparator, fixtures.swift, fixtures.typeScript);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.json.ok, true);
  assert.equal(result.json.details.summary.actorHopInstrumentedWorkloadCount, 3);
});

test("runtime comparator exits nonzero on a durability mismatch", () => {
  const fixtures = runtimeFixture(100, 100);
  fixtures.swift.metrics[2].samples[0].pendingMutationCount = 1;
  const result = run(runtimeComparator, fixtures.swift, fixtures.typeScript);
  assert.equal(result.status, 1);
  assert.equal(
    result.json.details.comparisons[2].correctness.pendingCountParity,
    false,
  );
});

test("ratio overrides are explicit and testable", () => {
  const fixtures = coreFixture(110, 100);
  const result = run(coreComparator, fixtures.swift, fixtures.typeScript, {
    INSTANT_SWIFT_DATA_MAX_P50_RATIO: "1.1",
    INSTANT_SWIFT_DATA_MAX_P95_RATIO: "1.1",
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.json.policy.maxP50Ratio, 1.1);
});

assert.ok(readFileSync(coreComparator, "utf8").includes("process.exitCode = 1"));
assert.ok(readFileSync(runtimeComparator, "utf8").includes("process.exitCode = 1"));
