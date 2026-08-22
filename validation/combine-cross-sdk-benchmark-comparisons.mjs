#!/usr/bin/env node
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const [corePath, runtimePath] = process.argv.slice(2);
assert.ok(
  corePath && runtimePath,
  "Usage: combine-cross-sdk-benchmark-comparisons.mjs <core.json> <runtime.json>",
);

const core = JSON.parse(readFileSync(resolve(corePath), "utf8"));
const runtime = JSON.parse(readFileSync(resolve(runtimePath), "utf8"));
assert.equal(core.details.swiftRevision, runtime.details.swiftRevision);
assert.equal(core.details.upstreamRevision, runtime.details.upstreamRevision);

const coreFailures = core.details.summary.failureCount ?? Number(!core.ok);
const runtimeFailures = runtime.details.summary.failureCount ?? Number(!runtime.ok);
const result = {
  case: "benchmark.cross-sdk.v2-comparison",
  event: "release-mode-summary",
  ok: Boolean(core.ok && runtime.ok && coreFailures === 0 && runtimeFailures === 0),
  policy: {
    failClosed: true,
    note: "Every constituent correctness and performance comparison must pass before publication.",
  },
  details: {
    swiftRevision: core.details.swiftRevision,
    upstreamRevision: core.details.upstreamRevision,
    summary: {
      workloadCount:
        core.details.summary.workloadCount + runtime.details.summary.workloadCount,
      passCount:
        (core.details.summary.passCount ?? 0) + (runtime.details.summary.passCount ?? 0),
      failureCount: coreFailures + runtimeFailures,
      actorHopInstrumentedWorkloadCount:
        runtime.details.summary.actorHopInstrumentedWorkloadCount,
    },
    core,
    runtime,
  },
};

process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
if (!result.ok) process.exitCode = 1;
