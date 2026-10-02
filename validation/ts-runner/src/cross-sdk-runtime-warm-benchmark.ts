import assert from "node:assert/strict";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import "fake-indexeddb/auto";
import {
  benchmarkMetric,
  benchmarkUUID,
  disposeReactor,
  installBrowserEnvironment,
  integerArgument,
  loadRuntimeInternals,
  measured,
  OfflineNetworkListener,
  record,
  runtimeConfig,
  waitForLoaded,
  type BenchmarkMetric,
  type BenchmarkSample,
} from "./cross-sdk-runtime-benchmark.js";

// The warm-connection counterpart of the cross-SDK runtime benchmark (#403): one long-lived Reactor runs every round,
// as an app's does. Swift's side is `InstantSwiftDataCrossSDKWarmRuntimeBenchmarks` (suite `cross-sdk-runtime-warm`).
// Each round enqueues one write and flushes the persisted pending mutations (timed), then acknowledges it with
// `transact-ok` and flushes again (timed), the same operations the cold benchmark times on a fresh Reactor.
export const crossSDKWarmRuntimeBenchmarkContract = {
  version: 1,
  warmUpOperationCount: 3,
  metricNames: ["warm.pending-mutation-enqueue.update", "warm.reconnect-outbox-drain"],
} as const;

export interface CrossSDKWarmRuntimeBenchmarkResult {
  suite: "cross-sdk-runtime-warm";
  sdk: "typescript";
  contractVersion: 1;
  coreVersion: string;
  persistence: "canonical-indexeddb-semantics-fake-backend";
  iterations: number;
  timestampMs: number;
  ok: boolean;
  metrics: BenchmarkMetric[];
}

export async function runCrossSDKWarmRuntimeBenchmark(
  iterations = integerArgument("--iterations", 20),
): Promise<CrossSDKWarmRuntimeBenchmarkResult> {
  assert.ok(iterations > 0, "Iterations must be greater than zero.");
  installBrowserEnvironment();
  const core = await loadRuntimeInternals();
  const samples = new Map<string, BenchmarkSample[]>();
  const reactor = new core.Reactor(
    runtimeConfig(benchmarkUUID(20_000)),
    core.IndexedDBStorage,
    OfflineNetworkListener,
  );
  reactor._setAttrs([]);
  await waitForLoaded(reactor);

  const warmUp = crossSDKWarmRuntimeBenchmarkContract.warmUpOperationCount;
  for (let round = 0; round < warmUp + iterations; round += 1) {
    const todoId = benchmarkUUID(30_000 + round);
    const transaction = core.tx.todos[todoId].update({
      text: `Warm cross-SDK runtime todo ${round}`,
      isCompleted: false,
      createdAt: new Date(1_700_000_000_000 + round),
    });
    const enqueueDuration = await measured(async () => {
      const result = await reactor.pushTx([transaction]);
      assert.equal(result.status, "enqueued");
      await reactor.kv.flush();
    });
    const pendingCount = reactor._pendingMutations().size;
    assert.equal(pendingCount, 1);

    const drainDuration = await measured(async () => {
      const pendingIDs = [...reactor._pendingMutations().keys()] as string[];
      for (const [index, eventId] of pendingIDs.entries()) {
        reactor._handleReceive(0, {
          op: "transact-ok",
          "client-event-id": eventId,
          "tx-id": round * 100 + index + 1,
        });
      }
      reactor._updatePendingMutations((pending: Map<string, unknown>) => {
        for (const eventId of pendingIDs) pending.delete(eventId);
      });
      await reactor.kv.flush();
    });
    assert.equal(reactor._pendingMutations().size, 0);

    const iteration = round - warmUp;
    if (iteration < 0) continue;
    record(samples, "warm.pending-mutation-enqueue.update", {
      iteration,
      durationNanoseconds: enqueueDuration,
      operationCount: 1,
      pendingMutationCount: pendingCount,
    });
    record(samples, "warm.reconnect-outbox-drain", {
      iteration,
      durationNanoseconds: drainDuration,
      operationCount: 1,
      resultCount: 1,
      pendingMutationCount: 0,
    });
  }
  disposeReactor(reactor);

  const metrics = crossSDKWarmRuntimeBenchmarkContract.metricNames.map((name) =>
    benchmarkMetric(name, samples.get(name) ?? []),
  );
  return {
    suite: "cross-sdk-runtime-warm",
    sdk: "typescript",
    contractVersion: 1,
    coreVersion: core.version,
    persistence: "canonical-indexeddb-semantics-fake-backend",
    iterations,
    timestampMs: Date.now(),
    ok: metrics.every((metric) => metric.samples.length === iterations),
    metrics,
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = await runCrossSDKWarmRuntimeBenchmark();
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}
