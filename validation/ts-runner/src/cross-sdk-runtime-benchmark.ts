import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import "fake-indexeddb/auto";

export const crossSDKRuntimeBenchmarkContract = {
  version: 1,
  mutationCount: 1,
  metricNames: [
    "pending-mutation-enqueue.update",
    "offline-restore.relaunch",
    "reconnect-outbox-drain",
  ],
} as const;

interface BenchmarkSample {
  iteration: number;
  durationNanoseconds: number;
  operationCount?: number;
  resultCount?: number;
  pendingMutationCount?: number;
}

interface BenchmarkMetric {
  name: string;
  unit: "nanoseconds";
  samples: BenchmarkSample[];
  minNanoseconds: number;
  p50Nanoseconds: number;
  p95Nanoseconds: number;
  maxNanoseconds: number;
  averageNanoseconds: number;
}

export interface CrossSDKRuntimeBenchmarkResult {
  suite: "cross-sdk-runtime";
  sdk: "typescript";
  contractVersion: 1;
  coreVersion: string;
  persistence: "canonical-indexeddb-semantics-fake-backend";
  iterations: number;
  timestampMs: number;
  ok: boolean;
  metrics: BenchmarkMetric[];
}

export async function runCrossSDKRuntimeBenchmark(
  iterations = integerArgument("--iterations", 5),
): Promise<CrossSDKRuntimeBenchmarkResult> {
  assert.ok(iterations > 0, "Iterations must be greater than zero.");
  installBrowserEnvironment();
  const core = await loadRuntimeInternals();
  const samples = new Map<string, BenchmarkSample[]>();

  for (let iteration = 0; iteration < iterations; iteration += 1) {
    const appId = benchmarkUUID(iteration);
    const first = new core.Reactor(
      runtimeConfig(appId),
      core.IndexedDBStorage,
      OfflineNetworkListener,
    );
    first._setAttrs([]);
    await waitForLoaded(first);

    const todoId = benchmarkUUID(iteration + 10_000);
    const transaction = core.tx.todos[todoId].update({
      text: `Cross-SDK runtime todo ${iteration}`,
      isCompleted: false,
      createdAt: new Date(1_700_000_000_000 + iteration),
    });
    const enqueueDuration = await measured(async () => {
      const result = await first.pushTx([transaction]);
      assert.equal(result.status, "enqueued");
      await first.kv.flush();
    });
    assert.equal(first._pendingMutations().size, crossSDKRuntimeBenchmarkContract.mutationCount);
    record(samples, "pending-mutation-enqueue.update", {
      iteration,
      durationNanoseconds: enqueueDuration,
      operationCount: 1,
      pendingMutationCount: first._pendingMutations().size,
    });
    disposeReactor(first);

    let restored: any;
    const restoreDuration = await measured(async () => {
      restored = new core.Reactor(
        runtimeConfig(appId),
        core.IndexedDBStorage,
        OfflineNetworkListener,
      );
      restored._setAttrs([]);
      await waitForLoaded(restored);
      assert.equal(
        restored._pendingMutations().size,
        crossSDKRuntimeBenchmarkContract.mutationCount,
      );
    });
    record(samples, "offline-restore.relaunch", {
      iteration,
      durationNanoseconds: restoreDuration,
      resultCount: 1,
      pendingMutationCount: restored._pendingMutations().size,
    });

    const drainDuration = await measured(async () => {
      const pendingIDs = [...restored._pendingMutations().keys()] as string[];
      for (const [index, eventId] of pendingIDs.entries()) {
        restored._handleReceive(0, {
          op: "transact-ok",
          "client-event-id": eventId,
          "tx-id": iteration * 100 + index + 1,
        });
      }
      restored._updatePendingMutations((pending: Map<string, unknown>) => {
        for (const eventId of pendingIDs) pending.delete(eventId);
      });
      await restored.kv.flush();
    });
    assert.equal(restored._pendingMutations().size, 0);
    record(samples, "reconnect-outbox-drain", {
      iteration,
      durationNanoseconds: drainDuration,
      operationCount: crossSDKRuntimeBenchmarkContract.mutationCount,
      resultCount: crossSDKRuntimeBenchmarkContract.mutationCount,
      pendingMutationCount: 0,
    });
    disposeReactor(restored);
  }

  const metrics = crossSDKRuntimeBenchmarkContract.metricNames.map((name) =>
    benchmarkMetric(name, samples.get(name) ?? []),
  );
  return {
    suite: "cross-sdk-runtime",
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

function installBrowserEnvironment() {
  const globals = globalThis as any;
  globals.window ??= { location: { search: "" } };
  globals.BroadcastChannel = undefined;
}

class OfflineNetworkListener {
  static getIsOnline(): Promise<boolean> {
    return new Promise(() => {});
  }

  static listen(_callback: (isOnline: boolean) => void) {
    return () => {};
  }
}

async function loadRuntimeInternals() {
  const packageEntry = fileURLToPath(import.meta.resolve("@instantdb/core"));
  const dist = dirname(packageEntry);
  const module = async (path: string) => import(pathToFileURL(resolve(dist, path)).href);
  const [reactorModule, indexedDBModule, txModule, packageManifest] = await Promise.all([
    module("Reactor.js"),
    module("IndexedDBStorage.js"),
    module("instatx.js"),
    import("@instantdb/core/package.json", { with: { type: "json" } }),
  ]);
  return {
    Reactor: reactorModule.default,
    IndexedDBStorage: indexedDBModule.default,
    tx: txModule.tx,
    version: packageManifest.default.version as string,
  };
}

function runtimeConfig(appId: string) {
  return {
    appId,
    apiURI: "https://api.instantdb.com",
    websocketURI: "wss://api.instantdb.com/runtime/session",
    pendingTxCleanupTimeout: 0,
    pendingMutationCleanupThreshold: 0,
  };
}

async function waitForLoaded(reactor: any) {
  await reactor.querySubs.waitForMetaToLoad();
  await reactor.kv.waitForMetaToLoad();
  await reactor.kv.waitForKeyToLoad("pendingMutations");
  await reactor.querySubs.flush();
  await reactor.kv.flush();
}

function disposeReactor(reactor: any) {
  reactor.shutdown();
  for (const persisted of [reactor.querySubs, reactor.kv, reactor._syncTable?.subs]) {
    if (!persisted) continue;
    if (persisted._nextSave) clearTimeout(persisted._nextSave);
    if (persisted._nextGc) clearTimeout(persisted._nextGc);
    persisted._nextSave = null;
    persisted._nextGc = null;
  }
}

function record(
  samples: Map<string, BenchmarkSample[]>,
  name: string,
  sample: BenchmarkSample,
) {
  const values = samples.get(name) ?? [];
  values.push(sample);
  samples.set(name, values);
}

function benchmarkMetric(name: string, samples: BenchmarkSample[]): BenchmarkMetric {
  const durations = samples.map((sample) => sample.durationNanoseconds).sort((a, b) => a - b);
  return {
    name,
    unit: "nanoseconds",
    samples,
    minNanoseconds: durations[0] ?? 0,
    p50Nanoseconds: percentile(durations, 0.5),
    p95Nanoseconds: percentile(durations, 0.95),
    maxNanoseconds: durations.at(-1) ?? 0,
    averageNanoseconds:
      durations.reduce((sum, duration) => sum + duration, 0) / Math.max(durations.length, 1),
  };
}

function percentile(sorted: number[], fraction: number): number {
  if (sorted.length === 0) return 0;
  const index = Math.ceil((sorted.length - 1) * fraction);
  return sorted[Math.min(index, sorted.length - 1)];
}

async function measured(operation: () => Promise<void>): Promise<number> {
  const start = process.hrtime.bigint();
  await operation();
  return Number(process.hrtime.bigint() - start);
}

function integerArgument(name: string, fallback: number): number {
  const index = process.argv.indexOf(name);
  if (index < 0) return fallback;
  const value = Number(process.argv[index + 1]);
  assert.ok(Number.isSafeInteger(value) && value > 0, `${name} must be a positive integer.`);
  return value;
}

function benchmarkUUID(index: number): string {
  return `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = await runCrossSDKRuntimeBenchmark();
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}
