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
assert.equal(core.ok, true);
assert.equal(runtime.ok, true);
assert.equal(core.details.swiftRevision, runtime.details.swiftRevision);
assert.equal(core.details.upstreamRevision, runtime.details.upstreamRevision);

const result = {
  case: "benchmark.cross-sdk.v1-comparison",
  event: "release-mode-summary",
  ok: true,
  details: {
    swiftRevision: core.details.swiftRevision,
    upstreamRevision: core.details.upstreamRevision,
    summary: {
      workloadCount:
        core.details.summary.workloadCount + runtime.details.summary.workloadCount,
      meetsOrExceedsCount:
        core.details.summary.meetsOrExceedsCount
        + runtime.details.summary.meetsOrExceedsCount,
      optimizationTargetCount:
        core.details.summary.optimizationTargetCount
        + runtime.details.summary.optimizationTargetCount,
      actorHopInstrumentedWorkloadCount:
        runtime.details.summary.actorHopInstrumentedWorkloadCount,
    },
    core,
    runtime,
  },
};

process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
