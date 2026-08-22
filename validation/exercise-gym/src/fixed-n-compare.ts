/**
 * Fixed-N parity comparison: identical write counts for TS (+ optional Swift metrics via files).
 * Measures wire sizes, step counts, and reports local store kind (TS MemoryStore has no SQLite).
 */
import { mkdirSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { openGemClients, makeRunId, newEntityId, resolveAppCredentials } from "./client.ts";
import { MetricsCollector, sleep } from "./metrics.ts";

const outDir = process.env.OUT ?? join(process.cwd(), "artifacts", "fixed-n-compare");
const N_SIMPLE = Number(process.env.N_SIMPLE ?? "50");
const N_COMPLEX = Number(process.env.N_COMPLEX ?? "10");
const CHAPTERS = 2;
const BLOCKS = 3;
const ANNS = 2;

mkdirSync(outDir, { recursive: true });
const { appId, adminToken } = resolveAppCredentials();
const runId = makeRunId();

const simple = await runSimple();
const complex = await runComplex();

// Attach Swift results if present
const swiftSimplePath = join(outDir, "swift-simple.json");
const swiftComplexPath = join(outDir, "swift-complex.json");
const report = {
  runId,
  appId,
  apiURI: process.env.INSTANT_API_URI ?? "https://api.instantdb.com",
  N_SIMPLE,
  N_COMPLEX,
  graphPerComplexWrite: {
    documents: 1,
    chapters: CHAPTERS,
    blocks: CHAPTERS * BLOCKS,
    annotations: CHAPTERS * BLOCKS * ANNS,
    entities: 1 + CHAPTERS + CHAPTERS * BLOCKS + CHAPTERS * BLOCKS * ANNS,
  },
  typescript: { simple, complex },
  swift: {
    simple: existsSync(swiftSimplePath) ? JSON.parse(readFileSync(swiftSimplePath, "utf8")) : null,
    complex: existsSync(swiftComplexPath) ? JSON.parse(readFileSync(swiftComplexPath, "utf8")) : null,
  },
  notes: [
    "TS gym client uses MemoryStore (in-process Map) — no SQLite file on disk.",
    "Swift InstantRuntime uses SQLite persistence; path recorded in swift-*.json when measured.",
    "Wire shape for Instant transact is op=transact + tx-steps of [op, entityId, attrId, value] add-triple rows.",
    "Fixed-N runs make write counts identical; timed races do not.",
  ],
};
writeFileSync(join(outDir, "comparison.json"), `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify({ event: "fixed-n-complete", outDir, reportPath: join(outDir, "comparison.json") }, null, 2));

async function runSimple() {
  const clients = await openGemClients({
    appId,
    adminToken,
    runId,
    suite: "fixed-simple",
    side: "typescript",
    descriptor: "ts-fixed-simple",
  });
  const metrics = new MetricsCollector();
  metrics.captureNodeBaseline();
  metrics.startSampling();
  const counterId = newEntityId();
  let lastObserved = 0;
  const unsub = clients.db.subscribeQuery(
    { counters: { $: { where: { id: counterId } } } },
    (resp: any) => {
      const rows = Object.values(resp?.data?.counters ?? {});
      const row = rows.find((r: any) => r?.id === counterId) as any;
      if (row && typeof row.seq === "number") lastObserved = row.seq;
    },
  );
  for (let seq = 1; seq <= N_SIMPLE; seq += 1) {
    const sent = Date.now();
    await clients.db.transact(
      clients.db.tx.counters[counterId].update({
        runId,
        name: "fixed",
        value: seq,
        seq,
        clientId: clients.identity.clientId,
        descriptor: clients.identity.descriptor,
        payloadBytes: 64,
        updatedAtMs: sent,
      }),
    );
    metrics.recordLocalAck();
    const deadline = Date.now() + 5_000;
    while (lastObserved < seq && Date.now() < deadline) await sleep(2);
    if (lastObserved >= seq) metrics.recordObserved(Date.now() - sent);
  }
  unsub();
  metrics.stopSampling();
  const wire = summarizeWire(clients.messageLog.all());
  clients.messageLog.writeJSONL(outDir, "ts-simple-messages.jsonl");
  const summary = {
    side: "typescript",
    suite: "simple",
    N: N_SIMPLE,
    identity: clients.identity,
    writes: N_SIMPLE,
    observed: metrics.throughput().writesObserved,
    latency: metrics.latencyStats(),
    peakAppRssMiB: metrics.peakAppRssBytes() / (1024 * 1024),
    peakRssMiB: metrics.peakRssBytes() / (1024 * 1024),
    nodeBaselineRssMiB: metrics.getNodeBaselineRssBytes() / (1024 * 1024),
    localStore: "MemoryStore (in-process Map — not SQLite)",
    localStoreBytes: null as number | null,
    wire,
  };
  writeFileSync(join(outDir, "ts-simple.json"), `${JSON.stringify(summary, null, 2)}\n`);
  clients.shutdown();
  console.log(JSON.stringify({ event: "ts-simple-done", observed: summary.observed, wire: summary.wire }));
  return summary;
}

async function runComplex() {
  const clients = await openGemClients({
    appId,
    adminToken,
    runId,
    suite: "fixed-complex",
    side: "typescript",
    descriptor: "ts-fixed-complex",
  });
  const metrics = new MetricsCollector();
  metrics.captureNodeBaseline();
  metrics.startSampling();
  let lastObs = 0;
  const unsub = clients.db.subscribeQuery(
    {
      documents: {
        $: { where: { runId } },
        chapters: { blocks: { annotations: {} } },
      },
    },
    (resp: any) => {
      const docs = Object.values(resp?.data?.documents ?? {}) as any[];
      for (const d of docs) {
        if (typeof d.seq === "number" && d.seq > lastObs) lastObs = d.seq;
      }
    },
  );
  for (let docSeq = 1; docSeq <= N_COMPLEX; docSeq += 1) {
    const documentId = newEntityId();
    const sent = Date.now();
    const chunks: any[] = [];
    chunks.push(
      clients.db.tx.documents[documentId].update({
        runId,
        title: `doc-${docSeq}`,
        seq: docSeq,
        clientId: clients.identity.clientId,
        descriptor: clients.identity.descriptor,
        summaryJSON: JSON.stringify({ docSeq }),
        updatedAtMs: sent,
      }),
    );
    for (let c = 0; c < CHAPTERS; c += 1) {
      const chapterId = newEntityId();
      chunks.push(
        clients.db.tx.chapters[chapterId]
          .update({
            runId,
            documentId,
            title: `ch-${c}`,
            order: c,
            seq: docSeq,
            clientId: clients.identity.clientId,
            descriptor: clients.identity.descriptor,
            bodyJSON: "{}",
            updatedAtMs: sent,
          })
          .link({ document: documentId }),
      );
      for (let b = 0; b < BLOCKS; b += 1) {
        const blockId = newEntityId();
        chunks.push(
          clients.db.tx.blocks[blockId]
            .update({
              runId,
              chapterId,
              kind: "paragraph",
              text: "x".repeat(80),
              order: b,
              seq: docSeq,
              clientId: clients.identity.clientId,
              descriptor: clients.identity.descriptor,
              metaJSON: "{}",
              updatedAtMs: sent,
            })
            .link({ chapter: chapterId }),
        );
        for (let a = 0; a < ANNS; a += 1) {
          const annotationId = newEntityId();
          chunks.push(
            clients.db.tx.annotations[annotationId]
              .update({
                runId,
                blockId,
                note: `n-${a}`,
                score: a,
                seq: docSeq,
                clientId: clients.identity.clientId,
                descriptor: clients.identity.descriptor,
                updatedAtMs: sent,
              })
              .link({ block: blockId }),
          );
        }
      }
    }
    await clients.db.transact(chunks);
    metrics.recordLocalAck();
    const deadline = Date.now() + 5_000;
    while (lastObs < docSeq && Date.now() < deadline) await sleep(5);
    if (lastObs >= docSeq) metrics.recordObserved(Date.now() - sent);
  }
  unsub();
  metrics.stopSampling();
  const wire = summarizeWire(clients.messageLog.all());
  clients.messageLog.writeJSONL(outDir, "ts-complex-messages.jsonl");
  const summary = {
    side: "typescript",
    suite: "complex",
    N: N_COMPLEX,
    identity: clients.identity,
    graphPerWrite: {
      documents: 1,
      chapters: CHAPTERS,
      blocks: CHAPTERS * BLOCKS,
      annotations: CHAPTERS * BLOCKS * ANNS,
      entities: 1 + CHAPTERS + CHAPTERS * BLOCKS + CHAPTERS * BLOCKS * ANNS,
      chunks: 1 + CHAPTERS + CHAPTERS * BLOCKS + CHAPTERS * BLOCKS * ANNS,
    },
    writes: N_COMPLEX,
    observed: metrics.throughput().writesObserved,
    latency: metrics.latencyStats(),
    peakAppRssMiB: metrics.peakAppRssBytes() / (1024 * 1024),
    peakRssMiB: metrics.peakRssBytes() / (1024 * 1024),
    nodeBaselineRssMiB: metrics.getNodeBaselineRssBytes() / (1024 * 1024),
    localStore: "MemoryStore (in-process Map — not SQLite)",
    localStoreBytes: null as number | null,
    wire,
  };
  writeFileSync(join(outDir, "ts-complex.json"), `${JSON.stringify(summary, null, 2)}\n`);
  clients.shutdown();
  console.log(JSON.stringify({ event: "ts-complex-done", observed: summary.observed, wire: summary.wire }));
  return summary;
}

function summarizeWire(msgs: any[]) {
  const txs = msgs.filter((m) => m.direction === "outbound" && m.op === "transact");
  const sizes = txs.map((m) => m.byteLength).sort((a: number, b: number) => a - b);
  const stepCounts: number[] = [];
  const stepOpHist: Record<string, number> = {};
  for (const t of txs) {
    try {
      const raw = t.bodyPreview.endsWith("…")
        ? null
        : JSON.parse(t.bodyPreview);
      if (!raw) {
        // truncated — try partial recovery of step count from add-triple occurrences
        const approx = (t.bodyPreview.match(/"add-triple"/g) || []).length;
        if (approx) stepCounts.push(approx);
        continue;
      }
      const steps = raw["tx-steps"];
      if (Array.isArray(steps)) {
        stepCounts.push(steps.length);
        for (const s of steps) {
          if (Array.isArray(s) && typeof s[0] === "string") {
            stepOpHist[s[0]] = (stepOpHist[s[0]] ?? 0) + 1;
          }
        }
      }
    } catch {
      /* ignore */
    }
  }
  return {
    frames: msgs.length,
    outbound: msgs.filter((m) => m.direction === "outbound").length,
    inbound: msgs.filter((m) => m.direction === "inbound").length,
    outboundTransact: txs.length,
    transactBytesTotal: sizes.reduce((a: number, b: number) => a + b, 0),
    transactBytesP50: sizes[Math.floor(sizes.length / 2)] ?? 0,
    transactBytesMax: sizes.at(-1) ?? 0,
    stepCountsUnique: [...new Set(stepCounts)],
    stepCountP50: stepCounts.length
      ? [...stepCounts].sort((a, b) => a - b)[Math.floor(stepCounts.length / 2)]
      : null,
    stepOpHist,
    sampleOps: [...new Set(msgs.map((m) => `${m.direction}:${m.op}`))],
  };
}
