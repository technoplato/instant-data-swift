/**
 * Correctness analysis over message logs, write events, and admin ground-truth queries.
 */
import { writeFileSync, mkdirSync, readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import type { MessageLog } from "./message-log.ts";
import type { GemClients } from "./client.ts";

export interface WriteEventRecord {
  eventId: string;
  suite: string;
  side: string;
  op: string;
  entityKind: string;
  entityId: string;
  seq: number;
  clientId: string;
  descriptor: string;
  sentAtMs: number;
  localAckAtMs?: number;
  observedAtMs?: number;
  rttMs?: number;
  payloadBytes: number;
  meta?: Record<string, unknown>;
}

export interface AnalysisReport {
  ok: boolean;
  runId: string;
  suite: string;
  checks: Array<{ name: string; ok: boolean; detail: string }>;
  messageSummary: ReturnType<MessageLog["summary"]> | null;
  writeEvents: {
    total: number;
    withClientId: number;
    withDescriptor: number;
    withPositiveRtt: number;
    uniqueEntityIds: number;
  };
  serverGroundTruth: Record<string, unknown>;
  failures: string[];
}

export async function analyzeRun(options: {
  clients: GemClients;
  messageLog: MessageLog;
  writeEvents: WriteEventRecord[];
  suite: string;
  outDir: string;
}): Promise<AnalysisReport> {
  const { clients, messageLog, writeEvents, suite, outDir } = options;
  const { identity, admin } = clients;
  const checks: AnalysisReport["checks"] = [];
  const failures: string[] = [];

  // 1. Every write event carries clientId + descriptor
  const withClientId = writeEvents.filter((e) => e.clientId && e.clientId.length > 0);
  const withDescriptor = writeEvents.filter((e) => e.descriptor && e.descriptor.length > 0);
  checks.push({
    name: "write-events-client-id",
    ok: withClientId.length === writeEvents.length && writeEvents.length > 0,
    detail: `${withClientId.length}/${writeEvents.length} events have clientId`,
  });
  checks.push({
    name: "write-events-descriptor",
    ok: withDescriptor.length === writeEvents.length && writeEvents.length > 0,
    detail: `${withDescriptor.length}/${writeEvents.length} events have descriptor`,
  });

  // 2. Message log non-empty for live core path
  const msgSummary = messageLog.summary();
  checks.push({
    name: "wire-messages-captured",
    ok: msgSummary.total > 0,
    detail: `${msgSummary.total} frames (out=${msgSummary.outbound}, in=${msgSummary.inbound})`,
  });
  checks.push({
    name: "message-log-client-id-coverage",
    ok: msgSummary.clientIdCoverage.withClientId === msgSummary.clientIdCoverage.total
      && msgSummary.total > 0,
    detail: `${msgSummary.clientIdCoverage.withClientId}/${msgSummary.clientIdCoverage.total} frames tagged with process clientId`,
  });

  // 3. Admin ground truth: counters + complex graph for this runId
  const runId = identity.runId;
  const ground = await admin.query({
    counters: { $: { where: { runId } } },
    documents: {
      $: { where: { runId } },
      chapters: {
        blocks: {
          annotations: {},
        },
      },
    },
    writeEvents: { $: { where: { runId } } },
  });

  const counters = asArray(ground?.counters);
  const documents = asArray(ground?.documents);
  const serverWriteEvents = asArray(ground?.writeEvents);

  // Client id consistency on server rows
  const counterClientIds = counters.map((c: any) => c.clientId).filter(Boolean);
  const allCounterClientIdsMatch =
    counters.length === 0
    || counterClientIds.every((id: string) => id === identity.clientId || id.length > 0);
  checks.push({
    name: "server-counter-client-ids-present",
    ok: counters.length === 0 || counterClientIds.length === counters.length,
    detail: `${counterClientIds.length}/${counters.length} counters have clientId on server`,
  });

  // Linked graph integrity for complex suites
  let linkedOk = true;
  let linkedDetail = "no documents (simple suite or empty)";
  if (documents.length > 0) {
    let chapterCount = 0;
    let blockCount = 0;
    let annotationCount = 0;
    let missingLinks = 0;
    for (const doc of documents as any[]) {
      const chapters = asArray(doc.chapters);
      chapterCount += chapters.length;
      if (chapters.length === 0) missingLinks += 1;
      for (const ch of chapters) {
        if (ch.clientId !== identity.clientId && !ch.clientId) missingLinks += 1;
        const blocks = asArray(ch.blocks);
        blockCount += blocks.length;
        for (const bl of blocks) {
          const anns = asArray(bl.annotations);
          annotationCount += anns.length;
          if (!bl.clientId || !bl.descriptor) missingLinks += 1;
          for (const an of anns) {
            if (!an.clientId || !an.descriptor) missingLinks += 1;
          }
        }
      }
    }
    linkedOk = missingLinks === 0 && chapterCount > 0 && blockCount > 0;
    linkedDetail =
      `docs=${documents.length} chapters=${chapterCount} blocks=${blockCount} annotations=${annotationCount} missingClientOrLinkFlags=${missingLinks}`;
  }
  checks.push({
    name: "complex-linked-graph-client-ids",
    ok: suite === "simple" || suite === "speed" || suite.includes("cap")
      ? true
      : linkedOk || documents.length === 0,
    detail: linkedDetail,
  });

  // 4. Observed RTT positive when observer path used
  const withRtt = writeEvents.filter((e) => typeof e.rttMs === "number" && e.rttMs >= 0);
  checks.push({
    name: "rtt-samples",
    ok: withRtt.length > 0 || writeEvents.length === 0,
    detail: `${withRtt.length} events with RTT (observer path)`,
  });

  // 5. Seq monotonicity per entity
  const byEntity = new Map<string, number[]>();
  for (const e of writeEvents) {
    const key = `${e.entityKind}:${e.entityId}`;
    const list = byEntity.get(key) ?? [];
    list.push(e.seq);
    byEntity.set(key, list);
  }
  let seqViolations = 0;
  for (const [, seqs] of byEntity) {
    for (let i = 1; i < seqs.length; i += 1) {
      if (seqs[i]! < seqs[i - 1]!) seqViolations += 1;
    }
  }
  checks.push({
    name: "seq-monotonic-per-entity",
    ok: seqViolations === 0,
    detail: `${seqViolations} seq regressions across ${byEntity.size} entities`,
  });

  for (const c of checks) {
    if (!c.ok) failures.push(`${c.name}: ${c.detail}`);
  }

  const report: AnalysisReport = {
    ok: failures.length === 0,
    runId,
    suite,
    checks,
    messageSummary: msgSummary,
    writeEvents: {
      total: writeEvents.length,
      withClientId: withClientId.length,
      withDescriptor: withDescriptor.length,
      withPositiveRtt: withRtt.length,
      uniqueEntityIds: byEntity.size,
    },
    serverGroundTruth: {
      counterCount: counters.length,
      documentCount: documents.length,
      serverWriteEventCount: serverWriteEvents.length,
      sampleCounter: counters[0] ?? null,
      sampleDocument: documents[0]
        ? {
            id: (documents[0] as any).id,
            title: (documents[0] as any).title,
            clientId: (documents[0] as any).clientId,
            descriptor: (documents[0] as any).descriptor,
            chapterCount: asArray((documents[0] as any).chapters).length,
          }
        : null,
    },
    failures,
  };

  mkdirSync(outDir, { recursive: true });
  writeFileSync(join(outDir, "analysis.json"), `${JSON.stringify(report, null, 2)}\n`);
  writeFileSync(
    join(outDir, "write-events.jsonl"),
    writeEvents.map((e) => JSON.stringify(e)).join("\n") + (writeEvents.length ? "\n" : ""),
  );
  writeFileSync(
    join(outDir, "server-ground-truth.json"),
    `${JSON.stringify(sanitizeGroundTruth(ground), null, 2)}\n`,
  );
  messageLog.writeJSONL(outDir);
  messageLog.writeSummary(outDir);

  return report;
}

function asArray(value: unknown): any[] {
  if (!value) return [];
  if (Array.isArray(value)) return value;
  if (typeof value === "object") return Object.values(value as object);
  return [];
}

function sanitizeGroundTruth(value: unknown): unknown {
  // Drop huge nested arrays of words if ever present; keep structure for analysis.
  try {
    return JSON.parse(JSON.stringify(value));
  } catch {
    return { error: "could not serialize ground truth" };
  }
}

export function loadJSON(path: string): unknown {
  if (!existsSync(path)) return null;
  return JSON.parse(readFileSync(path, "utf8"));
}
