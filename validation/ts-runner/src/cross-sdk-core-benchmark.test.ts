import assert from "node:assert/strict";
import test from "node:test";

import {
  crossSDKBenchmarkContract,
  runCrossSDKCoreBenchmark,
} from "./cross-sdk-core-benchmark.js";

test("cross-SDK core benchmark preserves the pinned Swift workload contract", async () => {
  const result = await runCrossSDKCoreBenchmark(1);

  assert.equal(result.suite, "cross-sdk-core");
  assert.equal(result.sdk, "typescript");
  assert.equal(result.contractVersion, 1);
  assert.equal(result.ok, true);
  assert.deepStrictEqual(
    result.metrics.map((metric) => metric.name),
    [...crossSDKBenchmarkContract.metricNames],
  );
  assert.ok(result.metrics.every((metric) => metric.samples.length === 1));
  assert.ok(result.metrics.every((metric) => metric.p50Nanoseconds > 0));
});
