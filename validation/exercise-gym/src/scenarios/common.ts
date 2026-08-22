import { performance } from "node:perf_hooks";
import type { GemClients } from "../client.ts";
import type { WriteEventRecord } from "../analyze.ts";
import { MetricsCollector, sleep } from "../metrics.ts";
import { newEntityId } from "../client.ts";

export interface CapOptions {
  /** Max app-attributed RSS MiB (rss - node baseline). Default 150. */
  maxAppRssMiB?: number;
  /** Max payload bytes per second (bandwidth throttle). */
  maxBytesPerSecond?: number;
  /** Target max process CPU percent (approx; self-throttle). */
  maxCpuPercent?: number;
  /** Max observed writes per second (speed throttle). */
  maxObservedPerSecond?: number;
}

export interface ScenarioOptions {
  durationSeconds: number;
  caps?: CapOptions;
  payloadBytes?: number;
  /** Chapters/blocks/annotations fan-out for complex writes */
  chaptersPerDoc?: number;
  blocksPerChapter?: number;
  annotationsPerBlock?: number;
}

export interface ScenarioResult {
  suite: string;
  side: string;
  ok: boolean;
  error?: string;
  writeEvents: WriteEventRecord[];
  metrics: ReturnType<MetricsCollector["snapshot"]>;
  details: Record<string, unknown>;
}

export function makePayload(size: number, seed: number): string {
  if (size <= 0) return "";
  const unit = `w${seed % 1000}=`;
  const repeats = Math.ceil(size / unit.length);
  return unit.repeat(repeats).slice(0, size);
}

/**
 * Subscribe and resolve when predicate matches. Returns observer RTT helper.
 */
export function observeUntil(
  db: any,
  query: object,
  predicate: (data: any) => boolean,
  timeoutMs = 5_000,
): Promise<{ data: any; observedAtMs: number }> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      unsub();
      reject(new Error(`observeUntil timed out after ${timeoutMs}ms`));
    }, timeoutMs);
    const unsub = db.subscribeQuery(query, (resp: any) => {
      if (resp?.error) return;
      const data = resp?.data ?? resp;
      if (predicate(data)) {
        clearTimeout(timer);
        unsub();
        resolve({ data, observedAtMs: Date.now() });
      }
    });
  });
}

export async function runSimpleWrites(
  clients: GemClients,
  options: ScenarioOptions,
): Promise<ScenarioResult> {
  const suite = "simple";
  const metrics = new MetricsCollector();
  metrics.captureNodeBaseline();
  metrics.startSampling();
  const writeEvents: WriteEventRecord[] = [];
  const counterId = newEntityId();
  const { db, identity } = clients;
  const durationMs = options.durationSeconds * 1000;
  const payloadBytes = options.payloadBytes ?? 64;
  const end = performance.now() + durationMs;
  let seq = 0;
  let bytesThisSecond = 0;
  let secondAnchor = performance.now();
  let error: string | undefined;

  // Dual process validity: also observe our own updates via subscription
  let lastObservedSeq = 0;
  const unsub = db.subscribeQuery(
    { counters: { $: { where: { id: counterId } } } },
    (resp: any) => {
      const rows = Object.values(resp?.data?.counters ?? resp?.counters ?? {});
      const row = rows.find((r: any) => r?.id === counterId) as any;
      if (row && typeof row.seq === "number" && row.seq > lastObservedSeq) {
        lastObservedSeq = row.seq;
      }
    },
  );

  try {
    while (performance.now() < end) {
      if (shouldThrottle(metrics, options.caps, bytesThisSecond, secondAnchor)) {
        await sleep(5);
        continue;
      }
      seq += 1;
      const sentAtMs = Date.now();
      const eventId = newEntityId();
      const payload = makePayload(payloadBytes, seq);
      metrics.recordWriteAttempt(payloadBytes);
      const localStart = performance.now();
      await db.transact(
        db.tx.counters[counterId].update({
          runId: identity.runId,
          name: "simple-counter",
          value: seq,
          seq,
          clientId: identity.clientId,
          descriptor: identity.descriptor,
          payloadBytes,
          updatedAtMs: sentAtMs,
        }),
      );
      const localAckAtMs = Date.now();
      metrics.recordLocalAck();

      // Wait for observation of this seq (self-subscribe = read path RTT)
      const deadline = performance.now() + 5_000;
      while (lastObservedSeq < seq && performance.now() < deadline) {
        await sleep(2);
      }
      const observedAtMs = Date.now();
      const rttMs = lastObservedSeq >= seq ? observedAtMs - sentAtMs : -1;
      if (rttMs >= 0) metrics.recordObserved(rttMs);

      writeEvents.push({
        eventId,
        suite,
        side: identity.side,
        op: "counter.upsert",
        entityKind: "counters",
        entityId: counterId,
        seq,
        clientId: identity.clientId,
        descriptor: identity.descriptor,
        sentAtMs,
        localAckAtMs,
        observedAtMs: rttMs >= 0 ? observedAtMs : undefined,
        rttMs: rttMs >= 0 ? rttMs : undefined,
        payloadBytes,
        meta: { localMs: performance.now() - localStart },
      });

      bytesThisSecond += payloadBytes;
      if (performance.now() - secondAnchor >= 1000) {
        bytesThisSecond = 0;
        secondAnchor = performance.now();
      }
    }
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  } finally {
    unsub();
    metrics.stopSampling();
  }

  return {
    suite,
    side: identity.side,
    ok: !error && writeEvents.some((e) => (e.rttMs ?? -1) >= 0),
    error,
    writeEvents,
    metrics: metrics.snapshot(),
    details: {
      counterId,
      lastSeq: seq,
      lastObservedSeq,
      payloadBytes,
      caps: options.caps ?? {},
    },
  };
}

export async function runComplexWrites(
  clients: GemClients,
  options: ScenarioOptions,
): Promise<ScenarioResult> {
  const suite = "complex";
  const metrics = new MetricsCollector();
  metrics.captureNodeBaseline();
  metrics.startSampling();
  const writeEvents: WriteEventRecord[] = [];
  const { db, identity } = clients;
  const durationMs = options.durationSeconds * 1000;
  const chaptersPerDoc = options.chaptersPerDoc ?? 2;
  const blocksPerChapter = options.blocksPerChapter ?? 3;
  const annotationsPerBlock = options.annotationsPerBlock ?? 2;
  const payloadBytes = options.payloadBytes ?? 128;
  const end = performance.now() + durationMs;
  let docSeq = 0;
  let bytesThisSecond = 0;
  let secondAnchor = performance.now();
  let error: string | undefined;
  let lastObservedDocSeq = 0;

  const unsub = db.subscribeQuery(
    {
      documents: {
        $: { where: { runId: identity.runId } },
        chapters: {
          blocks: {
            annotations: {},
          },
        },
      },
    },
    (resp: any) => {
      const docs = Object.values(resp?.data?.documents ?? resp?.documents ?? {}) as any[];
      for (const d of docs) {
        if (typeof d.seq === "number" && d.seq > lastObservedDocSeq) {
          lastObservedDocSeq = d.seq;
        }
      }
    },
  );

  try {
    while (performance.now() < end) {
      if (shouldThrottle(metrics, options.caps, bytesThisSecond, secondAnchor)) {
        await sleep(5);
        continue;
      }
      docSeq += 1;
      const documentId = newEntityId();
      const sentAtMs = Date.now();
      const chunks: any[] = [];
      const body = makePayload(payloadBytes, docSeq);

      chunks.push(
        db.tx.documents[documentId].update({
          runId: identity.runId,
          title: `doc-${docSeq}`,
          seq: docSeq,
          clientId: identity.clientId,
          descriptor: identity.descriptor,
          summaryJSON: JSON.stringify({ body, docSeq }),
          updatedAtMs: sentAtMs,
        }),
      );

      let fanoutBytes = payloadBytes;
      for (let c = 0; c < chaptersPerDoc; c += 1) {
        const chapterId = newEntityId();
        chunks.push(
          db.tx.chapters[chapterId]
            .update({
              runId: identity.runId,
              documentId,
              title: `ch-${docSeq}-${c}`,
              order: c,
              seq: docSeq,
              clientId: identity.clientId,
              descriptor: identity.descriptor,
              bodyJSON: JSON.stringify({ body, c }),
              updatedAtMs: sentAtMs,
            })
            .link({ document: documentId }),
        );
        fanoutBytes += payloadBytes;
        for (let b = 0; b < blocksPerChapter; b += 1) {
          const blockId = newEntityId();
          chunks.push(
            db.tx.blocks[blockId]
              .update({
                runId: identity.runId,
                chapterId,
                kind: b % 2 === 0 ? "paragraph" : "code",
                text: body.slice(0, 80),
                order: b,
                seq: docSeq,
                clientId: identity.clientId,
                descriptor: identity.descriptor,
                metaJSON: JSON.stringify({ b, c, docSeq }),
                updatedAtMs: sentAtMs,
              })
              .link({ chapter: chapterId }),
          );
          fanoutBytes += 80;
          for (let a = 0; a < annotationsPerBlock; a += 1) {
            const annotationId = newEntityId();
            chunks.push(
              db.tx.annotations[annotationId]
                .update({
                  runId: identity.runId,
                  blockId,
                  note: `note-${docSeq}-${c}-${b}-${a}`,
                  score: a,
                  seq: docSeq,
                  clientId: identity.clientId,
                  descriptor: identity.descriptor,
                  updatedAtMs: sentAtMs,
                })
                .link({ block: blockId }),
            );
            fanoutBytes += 32;
          }
        }
      }

      metrics.recordWriteAttempt(fanoutBytes);
      await db.transact(chunks);
      const localAckAtMs = Date.now();
      metrics.recordLocalAck();

      const deadline = performance.now() + 5_000;
      while (lastObservedDocSeq < docSeq && performance.now() < deadline) {
        await sleep(5);
      }
      const observedAtMs = Date.now();
      const rttMs = lastObservedDocSeq >= docSeq ? observedAtMs - sentAtMs : -1;
      if (rttMs >= 0) metrics.recordObserved(rttMs);

      writeEvents.push({
        eventId: newEntityId(),
        suite,
        side: identity.side,
        op: "document.graph.upsert",
        entityKind: "documents",
        entityId: documentId,
        seq: docSeq,
        clientId: identity.clientId,
        descriptor: identity.descriptor,
        sentAtMs,
        localAckAtMs,
        observedAtMs: rttMs >= 0 ? observedAtMs : undefined,
        rttMs: rttMs >= 0 ? rttMs : undefined,
        payloadBytes: fanoutBytes,
        meta: {
          chaptersPerDoc,
          blocksPerChapter,
          annotationsPerBlock,
          chunkCount: chunks.length,
        },
      });

      bytesThisSecond += fanoutBytes;
      if (performance.now() - secondAnchor >= 1000) {
        bytesThisSecond = 0;
        secondAnchor = performance.now();
      }
    }
  } catch (e) {
    error = e instanceof Error ? e.message : String(e);
  } finally {
    unsub();
    metrics.stopSampling();
  }

  return {
    suite,
    side: identity.side,
    ok: !error && writeEvents.some((e) => (e.rttMs ?? -1) >= 0),
    error,
    writeEvents,
    metrics: metrics.snapshot(),
    details: {
      lastDocSeq: docSeq,
      lastObservedDocSeq,
      chaptersPerDoc,
      blocksPerChapter,
      annotationsPerBlock,
      caps: options.caps ?? {},
    },
  };
}

function shouldThrottle(
  metrics: MetricsCollector,
  caps: CapOptions | undefined,
  bytesThisSecond: number,
  secondAnchor: number,
): boolean {
  if (!caps) return false;
  const snap = metrics.sample();
  if (
    caps.maxAppRssMiB != null
    && snap.appAttributedRssBytes / (1024 * 1024) >= caps.maxAppRssMiB
  ) {
    return true;
  }
  if (caps.maxBytesPerSecond != null && bytesThisSecond >= caps.maxBytesPerSecond) {
    return true;
  }
  if (caps.maxCpuPercent != null && metrics.cpuPercentApprox() >= caps.maxCpuPercent) {
    return true;
  }
  if (caps.maxObservedPerSecond != null) {
    const t = metrics.throughput();
    if (t.observedPerSecond >= caps.maxObservedPerSecond) return true;
  }
  void secondAnchor;
  return false;
}
