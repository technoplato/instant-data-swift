import assert from "node:assert/strict";
import test from "node:test";
import {
  crossSDKRuntimeBenchmarkContract,
  runCrossSDKRuntimeBenchmark,
} from "./cross-sdk-runtime-benchmark.js";

test("cross-SDK runtime benchmark preserves durable workload parity", async () => {
  const result = await runCrossSDKRuntimeBenchmark(1);

  assert.equal(result.suite, "cross-sdk-runtime");
  assert.equal(result.sdk, "typescript");
  assert.equal(result.contractVersion, 1);
  assert.equal(result.persistence, "canonical-indexeddb-semantics-fake-backend");
  assert.equal(result.ok, true);
  assert.deepEqual(
    result.metrics.map((metric) => metric.name),
    crossSDKRuntimeBenchmarkContract.metricNames,
  );
  assert.deepEqual(
    result.metrics.map((metric) => metric.samples[0]?.pendingMutationCount),
    [1, 1, 0],
  );
});
