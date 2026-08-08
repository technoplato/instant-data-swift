/**
 * Process metrics for the exercise gem.
 *
 * Memory contract:
 * - Primary gate: process RSS (physical-ish resident set)
 * - App-attributed memory ≈ rss - nodeBaselineRss (Node process at idle after boot)
 * - Never use VSZ as a gate
 * - Secondary: V8 heapUsed for JS heap pressure
 */
import { cpus, freemem, totalmem } from "node:os";
import { performance } from "node:perf_hooks";

export interface MemorySample {
  atMs: number;
  rssBytes: number;
  heapUsedBytes: number;
  heapTotalBytes: number;
  externalBytes: number;
  arrayBuffersBytes: number;
  /** rss - baseline; can be negative briefly after GC */
  appAttributedRssBytes: number;
  freememBytes: number;
}

export interface LatencyStats {
  count: number;
  minMs: number;
  maxMs: number;
  p50Ms: number;
  p95Ms: number;
  p99Ms: number;
  meanMs: number;
}

export interface ThroughputStats {
  writesAttempted: number;
  writesLocalAcked: number;
  writesObserved: number;
  wallSeconds: number;
  observedPerSecond: number;
  localAckPerSecond: number;
  bytesWritten: number;
  bytesPerSecond: number;
}

export class MetricsCollector {
  readonly startedAtMs = Date.now();
  readonly startedAtPerf = performance.now();
  private readonly samples: MemorySample[] = [];
  private readonly latenciesMs: number[] = [];
  private nodeBaselineRss = 0;
  private writesAttempted = 0;
  private writesLocalAcked = 0;
  private writesObserved = 0;
  private bytesWritten = 0;
  private sampleTimer: ReturnType<typeof setInterval> | null = null;
  private cpuStart = process.cpuUsage();
  private wallStart = performance.now();

  constructor(private readonly sampleIntervalMs = 250) {}

  /** Call once after Node + Instant init, before workload. */
  captureNodeBaseline(): void {
    // Encourage a quiet baseline sample.
    if (typeof globalThis.gc === "function") {
      try {
        globalThis.gc();
      } catch {
        /* optional --expose-gc */
      }
    }
    this.nodeBaselineRss = process.memoryUsage().rss;
  }

  getNodeBaselineRssBytes(): number {
    return this.nodeBaselineRss;
  }

  startSampling(): void {
    this.sample();
    this.sampleTimer = setInterval(() => this.sample(), this.sampleIntervalMs);
    this.sampleTimer.unref?.();
  }

  stopSampling(): void {
    if (this.sampleTimer) {
      clearInterval(this.sampleTimer);
      this.sampleTimer = null;
    }
    this.sample();
  }

  sample(): MemorySample {
    const mu = process.memoryUsage();
    const sample: MemorySample = {
      atMs: Date.now(),
      rssBytes: mu.rss,
      heapUsedBytes: mu.heapUsed,
      heapTotalBytes: mu.heapTotal,
      externalBytes: mu.external,
      arrayBuffersBytes: mu.arrayBuffers,
      appAttributedRssBytes: Math.max(0, mu.rss - this.nodeBaselineRss),
      freememBytes: freemem(),
    };
    this.samples.push(sample);
    return sample;
  }

  recordWriteAttempt(payloadBytes = 0): void {
    this.writesAttempted += 1;
    this.bytesWritten += payloadBytes;
  }

  recordLocalAck(): void {
    this.writesLocalAcked += 1;
  }

  recordObserved(rttMs: number): void {
    this.writesObserved += 1;
    if (Number.isFinite(rttMs) && rttMs >= 0) {
      this.latenciesMs.push(rttMs);
    }
  }

  wallSeconds(): number {
    return (performance.now() - this.startedAtPerf) / 1000;
  }

  peakAppRssBytes(): number {
    if (this.samples.length === 0) return 0;
    return Math.max(...this.samples.map((s) => s.appAttributedRssBytes));
  }

  peakRssBytes(): number {
    if (this.samples.length === 0) return process.memoryUsage().rss;
    return Math.max(...this.samples.map((s) => s.rssBytes));
  }

  latencyStats(): LatencyStats {
    return percentileStats(this.latenciesMs);
  }

  throughput(): ThroughputStats {
    const wall = Math.max(this.wallSeconds(), 1e-6);
    return {
      writesAttempted: this.writesAttempted,
      writesLocalAcked: this.writesLocalAcked,
      writesObserved: this.writesObserved,
      wallSeconds: wall,
      observedPerSecond: this.writesObserved / wall,
      localAckPerSecond: this.writesLocalAcked / wall,
      bytesWritten: this.bytesWritten,
      bytesPerSecond: this.bytesWritten / wall,
    };
  }

  cpuPercentApprox(): number {
    const usage = process.cpuUsage(this.cpuStart);
    const wallMs = performance.now() - this.wallStart;
    const cpuMs = (usage.user + usage.system) / 1000;
    const cores = Math.max(cpus().length, 1);
    return (cpuMs / wallMs) * 100 / cores;
  }

  snapshot() {
    return {
      nodeBaselineRssBytes: this.nodeBaselineRss,
      peakRssBytes: this.peakRssBytes(),
      peakAppAttributedRssBytes: this.peakAppRssBytes(),
      peakAppAttributedRssMiB: this.peakAppRssBytes() / (1024 * 1024),
      peakRssMiB: this.peakRssBytes() / (1024 * 1024),
      lastSample: this.samples.at(-1) ?? null,
      sampleCount: this.samples.length,
      latency: this.latencyStats(),
      throughput: this.throughput(),
      cpuPercentApprox: this.cpuPercentApprox(),
      host: {
        totalmemBytes: totalmem(),
        freememBytes: freemem(),
        cpuCount: cpus().length,
        cpuModel: cpus()[0]?.model ?? "unknown",
      },
      samples: this.samples,
    };
  }
}

export function percentileStats(values: number[]): LatencyStats {
  if (values.length === 0) {
    return {
      count: 0,
      minMs: 0,
      maxMs: 0,
      p50Ms: 0,
      p95Ms: 0,
      p99Ms: 0,
      meanMs: 0,
    };
  }
  const sorted = [...values].sort((a, b) => a - b);
  const pick = (p: number) => {
    const idx = Math.min(sorted.length - 1, Math.max(0, Math.ceil(p * sorted.length) - 1));
    return sorted[idx]!;
  };
  const sum = sorted.reduce((a, b) => a + b, 0);
  return {
    count: sorted.length,
    minMs: sorted[0]!,
    maxMs: sorted[sorted.length - 1]!,
    p50Ms: pick(0.5),
    p95Ms: pick(0.95),
    p99Ms: pick(0.99),
    meanMs: sum / sorted.length,
  };
}

export function bytesToMiB(bytes: number): number {
  return bytes / (1024 * 1024);
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
