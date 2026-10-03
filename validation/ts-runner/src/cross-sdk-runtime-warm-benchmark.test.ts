import assert from "node:assert/strict";
import test from "node:test";
import {
  crossSDKWarmRuntimeBenchmarkContract,
  runCrossSDKWarmRuntimeBenchmark,
} from "./cross-sdk-runtime-warm-benchmark.js";

test("warm cross-SDK runtime benchmark runs every round on one Reactor", async () => {
  const result = await runCrossSDKWarmRuntimeBenchmark(2);

  assert.equal(result.suite, "cross-sdk-runtime-warm");
  assert.equal(result.sdk, "typescript");
  assert.equal(result.contractVersion, 1);
  assert.equal(result.ok, true);
  assert.deepEqual(
    result.metrics.map((metric) => metric.name),
    crossSDKWarmRuntimeBenchmarkContract.metricNames,
  );
  assert.deepEqual(
    result.metrics.map((metric) => metric.samples.map((sample) => sample.pendingMutationCount)),
    [
      [1, 1],
      [0, 0],
    ],
  );
});
