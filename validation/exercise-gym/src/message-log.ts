/**
 * Wire-level Instant message log.
 *
 * Wraps global WebSocket so every send/receive is recorded with:
 * - direction (outbound/inbound)
 * - clientId + descriptor of this process
 * - op / type extracted from Instant frames when present
 * - payload size + truncated body for analysis
 *
 * Docker/self-host is optional: when server logs are unavailable (hosted Instant),
 * this client log is the authoritative message artifact.
 */
import { appendFileSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

export interface MessageRecord {
  id: number;
  atMs: number;
  direction: "outbound" | "inbound";
  clientId: string;
  descriptor: string;
  runId: string;
  suite: string;
  side: string;
  /** Instant op / type field when parseable */
  op: string | null;
  event: string | null;
  /** Transaction / event ids when present */
  transactionIds: string[];
  clientEventId: string | null;
  byteLength: number;
  /** Truncated JSON/text for offline analysis */
  bodyPreview: string;
  parseError?: string;
}

export class MessageLog {
  private records: MessageRecord[] = [];
  private nextId = 1;
  private OriginalWebSocket: typeof WebSocket | null = null;
  private installed = false;

  constructor(
    private readonly identity: {
      clientId: string;
      descriptor: string;
      runId: string;
      suite: string;
      side: string;
    },
    private readonly maxBodyPreview = 100_000,
    private readonly maxRecords = 50_000,
  ) {}

  updateIdentity(partial: Partial<typeof this.identity>): void {
    Object.assign(this.identity, partial);
  }

  install(): void {
    if (this.installed) return;
    const self = this;
    const G = globalThis as any;
    this.OriginalWebSocket = G.WebSocket;
    if (!this.OriginalWebSocket) {
      throw new Error("WebSocket is not available on globalThis; install ws polyfill first.");
    }
    const Original = this.OriginalWebSocket;

    class LoggingWebSocket extends Original {
      constructor(url: string | URL, protocols?: string | string[]) {
        super(url as any, protocols as any);
        this.addEventListener("message", (event: MessageEvent) => {
          self.record("inbound", event.data);
        });
        const originalSend = this.send.bind(this);
        this.send = (data: any) => {
          self.record("outbound", data);
          return originalSend(data);
        };
      }
    }

    G.WebSocket = LoggingWebSocket;
    this.installed = true;
  }

  uninstall(): void {
    if (!this.installed || !this.OriginalWebSocket) return;
    (globalThis as any).WebSocket = this.OriginalWebSocket;
    this.installed = false;
  }

  private record(direction: "outbound" | "inbound", data: unknown): void {
    if (this.records.length >= this.maxRecords) return;
    const text = toText(data);
    const parsed = tryParse(text);
    const op =
      pickString(parsed, ["op", "type", "event", "method"]) ??
      null;
    const event = pickString(parsed, ["event", "type"]) ?? null;
    const transactionIds = collectTransactionIds(parsed);
    const clientEventId =
      pickString(parsed, ["client-event-id", "clientEventId", "event-id", "eventId"]) ??
      null;

    this.records.push({
      id: this.nextId++,
      atMs: Date.now(),
      direction,
      clientId: this.identity.clientId,
      descriptor: this.identity.descriptor,
      runId: this.identity.runId,
      suite: this.identity.suite,
      side: this.identity.side,
      op,
      event,
      transactionIds,
      clientEventId,
      byteLength: Buffer.byteLength(text, "utf8"),
      bodyPreview: text.length > this.maxBodyPreview
        ? `${text.slice(0, this.maxBodyPreview)}…`
        : text,
      ...(parsed === undefined && text.length > 0
        ? { parseError: "non-json" }
        : {}),
    });
  }

  all(): MessageRecord[] {
    return this.records;
  }

  summary() {
    const byOp = new Map<string, number>();
    let outbound = 0;
    let inbound = 0;
    let totalBytes = 0;
    for (const r of this.records) {
      if (r.direction === "outbound") outbound += 1;
      else inbound += 1;
      totalBytes += r.byteLength;
      const key = r.op ?? "(unknown)";
      byOp.set(key, (byOp.get(key) ?? 0) + 1);
    }
    return {
      total: this.records.length,
      outbound,
      inbound,
      totalBytes,
      byOp: Object.fromEntries(byOp),
      uniqueTransactionIds: new Set(
        this.records.flatMap((r) => r.transactionIds),
      ).size,
      clientIdCoverage: {
        withClientId: this.records.filter((r) => r.clientId.length > 0).length,
        total: this.records.length,
      },
    };
  }

  writeJSONL(dir: string, fileName = "messages.jsonl"): string {
    mkdirSync(dir, { recursive: true });
    const path = join(dir, fileName);
    writeFileSync(path, "");
    for (const r of this.records) {
      appendFileSync(path, `${JSON.stringify(r)}\n`);
    }
    return path;
  }

  writeSummary(dir: string, fileName = "messages.summary.json"): string {
    mkdirSync(dir, { recursive: true });
    const path = join(dir, fileName);
    writeFileSync(path, `${JSON.stringify(this.summary(), null, 2)}\n`);
    return path;
  }
}

function toText(data: unknown): string {
  if (typeof data === "string") return data;
  if (data instanceof ArrayBuffer) return Buffer.from(data).toString("utf8");
  if (ArrayBuffer.isView(data)) {
    return Buffer.from(data.buffer, data.byteOffset, data.byteLength).toString("utf8");
  }
  if (data && typeof data === "object" && "data" in (data as any)) {
    return toText((data as any).data);
  }
  try {
    return JSON.stringify(data);
  } catch {
    return String(data);
  }
}

function tryParse(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

function pickString(value: unknown, keys: string[]): string | undefined {
  if (!value || typeof value !== "object") return undefined;
  const obj = value as Record<string, unknown>;
  for (const key of keys) {
    const v = obj[key];
    if (typeof v === "string" && v.length > 0) return v;
  }
  // nested common Instant shapes
  for (const nestedKey of ["body", "data", "msg", "message"]) {
    const nested = obj[nestedKey];
    const found = pickString(nested, keys);
    if (found) return found;
  }
  return undefined;
}

function collectTransactionIds(value: unknown): string[] {
  const out = new Set<string>();
  walk(value, (node) => {
    if (!node || typeof node !== "object") return;
    const obj = node as Record<string, unknown>;
    for (const key of [
      "tx-id",
      "txId",
      "transaction-id",
      "transactionId",
      "event-id",
      "eventId",
      "client-event-id",
    ]) {
      const v = obj[key];
      if (typeof v === "string" && v.length > 0) out.add(v);
      if (typeof v === "number") out.add(String(v));
    }
    if (Array.isArray(obj["tx-ids"])) {
      for (const id of obj["tx-ids"]) {
        if (typeof id === "string") out.add(id);
      }
    }
  });
  return [...out];
}

function walk(value: unknown, visit: (node: unknown) => void, depth = 0): void {
  if (depth > 8 || value == null) return;
  visit(value);
  if (Array.isArray(value)) {
    for (const item of value.slice(0, 50)) walk(item, visit, depth + 1);
    return;
  }
  if (typeof value === "object") {
    for (const v of Object.values(value as object).slice(0, 50)) {
      walk(v, visit, depth + 1);
    }
  }
}
