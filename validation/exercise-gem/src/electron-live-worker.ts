/**
 * Electron live worker: continuous simple writes + JSONL events on stdout.
 */
import { openGemClients, makeRunId, resolveAppCredentials } from "./client.ts";
import { MetricsCollector, sleep } from "./metrics.ts";
import { newEntityId } from "./client.ts";

const durationSeconds = Number(process.env.EXERCISE_GEM_LIVE_SECONDS ?? "120");
const { appId, adminToken } = resolveAppCredentials();
const runId = makeRunId();
const clients = await openGemClients({
  appId,
  adminToken,
  runId,
  suite: "electron-live",
  side: "electron",
  descriptor: `electron-live-${process.pid}`,
});

const metrics = new MetricsCollector();
metrics.captureNodeBaseline();
metrics.startSampling();

const counterId = newEntityId();
let seq = 0;
let lastObservedSeq = 0;
const unsub = clients.db.subscribeQuery(
  { counters: { $: { where: { id: counterId } } } },
  (resp: any) => {
    const rows = Object.values(resp?.data?.counters ?? resp?.counters ?? {});
    const row = rows.find((r: any) => r?.id === counterId) as any;
    if (row && typeof row.seq === "number" && row.seq > lastObservedSeq) {
      lastObservedSeq = row.seq;
    }
  },
);

const end = Date.now() + durationSeconds * 1000;
try {
  while (Date.now() < end) {
    seq += 1;
    const sentAtMs = Date.now();
    await clients.db.transact(
      clients.db.tx.counters[counterId].update({
        runId,
        name: "electron-live",
        value: seq,
        seq,
        clientId: clients.identity.clientId,
        descriptor: clients.identity.descriptor,
        payloadBytes: 64,
        updatedAtMs: sentAtMs,
      }),
    );
    metrics.recordLocalAck();
    const deadline = Date.now() + 5_000;
    while (lastObservedSeq < seq && Date.now() < deadline) {
      await sleep(2);
    }
    const observedAtMs = Date.now();
    const rttMs = lastObservedSeq >= seq ? observedAtMs - sentAtMs : -1;
    if (rttMs >= 0) metrics.recordObserved(rttMs);
    const sample = metrics.sample();
    console.log(
      JSON.stringify({
        type: "write",
        seq,
        rttMs: rttMs >= 0 ? rttMs : null,
        clientId: clients.identity.clientId,
        descriptor: clients.identity.descriptor,
        entityId: counterId,
        appRssMiB: sample.appAttributedRssBytes / (1024 * 1024),
      }),
    );
    if (seq % 10 === 0) {
      const snap = metrics.snapshot();
      console.log(
        JSON.stringify({
          type: "metrics",
          observedPerSecond: snap.throughput.observedPerSecond,
          rttP50Ms: snap.latency.p50Ms,
          appRssMiB: snap.peakAppAttributedRssMiB,
        }),
      );
    }
  }
} finally {
  unsub();
  metrics.stopSampling();
  clients.shutdown();
}
