#!/usr/bin/env node
/**
 * Instant exercise gem orchestrator.
 *
 * Suites:
 *   simple | complex | speed | memory-cap | bandwidth-cap | cpu-cap | all
 *   analyze-only (re-analyze last artifact dir)
 *   compare (TS vs Swift result JSON)
 *
 * Env:
 *   INSTANT_APP_ID, INSTANT_ADMIN_TOKEN (or SCRIBE_TEST_*)
 *   EXERCISE_GEM_DURATION_SECONDS (default 15 for quick, 60 for full)
 *   EXERCISE_GEM_MAX_APP_RSS_MIB (default 150)
 *
 * Issue: https://issues.knophy.com/issues/156
 */
import { mkdirSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { openGemClients, makeRunId, resolveAppCredentials } from "./client.ts";
import { analyzeRun, type WriteEventRecord } from "./analyze.ts";
import {
  runSimpleWrites,
  runComplexWrites,
  type ScenarioResult,
  type CapOptions,
} from "./scenarios/common.ts";
import { bytesToMiB } from "./metrics.ts";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const gemRoot = resolve(__dirname, "..");
const defaultArtifacts = resolve(gemRoot, "artifacts");

const suiteArg = flagValue("--suite") ?? "all";
const durationSeconds = Number(
  flagValue("--duration")
    ?? process.env.EXERCISE_GEM_DURATION_SECONDS
    ?? "15",
);
const maxAppRssMiB = Number(
  flagValue("--max-app-rss-mib")
    ?? process.env.EXERCISE_GEM_MAX_APP_RSS_MIB
    ?? "150",
);
const outDirArg = flagValue("--out");
const skipSwift = hasFlag("--skip-swift");
const skipTs = hasFlag("--skip-ts");
const swiftOnly = hasFlag("--swift-only");
const compareSwiftPath = flagValue("--swift-result");
const compareTsPath = flagValue("--ts-result");

const ALL_SUITES = [
  "simple",
  "complex",
  "speed",
  "memory-cap",
  "bandwidth-cap",
  "cpu-cap",
] as const;

type SuiteName = (typeof ALL_SUITES)[number];

async function main(): Promise<void> {
  if (suiteArg === "compare") {
    runCompare(compareTsPath, compareSwiftPath);
    return;
  }

  const runId = makeRunId();
  const outDir = outDirArg
    ?? join(
      defaultArtifacts,
      new Date().toISOString().replace(/[:.]/g, "-") + `-${runId.slice(0, 8)}`,
    );
  mkdirSync(outDir, { recursive: true });

  const suites: SuiteName[] =
    suiteArg === "all"
      ? [...ALL_SUITES]
      : suiteArg === "analyze-only"
        ? []
        : [suiteArg as SuiteName];

  console.log(JSON.stringify({
    event: "exercise-gem-start",
    runId,
    suites,
    durationSeconds,
    maxAppRssMiB,
    outDir,
    docker: "unavailable-or-not-used",
    note: "Hosted Instant + client wire message log; Docker self-host optional later.",
  }));

  const { appId, adminToken } = resolveAppCredentials();
  const report: any = {
    runId,
    createdAt: new Date().toISOString(),
    appId,
    durationSeconds,
    maxAppRssMiB,
    suites: {} as Record<string, unknown>,
    compare: null as unknown,
  };

  if (!skipTs && !swiftOnly) {
    for (const suite of suites) {
      console.log(`[gem] TS suite=${suite} duration=${durationSeconds}s`);
      const suiteDir = join(outDir, "typescript", suite);
      mkdirSync(suiteDir, { recursive: true });
      const clients = await openGemClients({
        appId,
        adminToken,
        runId,
        suite,
        side: "typescript",
        descriptor: `ts-node-${suite}-${process.pid}`,
      });
      try {
        const result = await runSuite(suite, clients, {
          durationSeconds: suiteDuration(suite, durationSeconds),
          caps: capsFor(suite, maxAppRssMiB),
          payloadBytes: suite === "bandwidth-cap" ? 8_192 : suite === "complex" ? 256 : 64,
          chaptersPerDoc: suite === "complex" ? 2 : 1,
          blocksPerChapter: suite === "complex" ? 3 : 1,
          annotationsPerBlock: suite === "complex" ? 2 : 1,
        });
        const analysis = await analyzeRun({
          clients,
          messageLog: clients.messageLog,
          writeEvents: result.writeEvents,
          suite,
          outDir: suiteDir,
        });
        // Persist writeEvents as Instant entities for server-side reconstruction
        await persistWriteEvents(clients, result.writeEvents);

        const suiteReport = {
          result: stripHuge(result),
          analysis,
          identity: clients.identity,
          artifacts: {
            dir: suiteDir,
            messages: join(suiteDir, "messages.jsonl"),
            analysis: join(suiteDir, "analysis.json"),
            writeEvents: join(suiteDir, "write-events.jsonl"),
            serverGroundTruth: join(suiteDir, "server-ground-truth.json"),
          },
        };
        writeFileSync(join(suiteDir, "suite-report.json"), `${JSON.stringify(suiteReport, null, 2)}\n`);
        report.suites[`typescript:${suite}`] = suiteReport;
        console.log(JSON.stringify({
          event: "suite-complete",
          side: "typescript",
          suite,
          ok: result.ok && analysis.ok,
          observedPerSecond: result.metrics.throughput.observedPerSecond,
          peakAppRssMiB: result.metrics.peakAppAttributedRssMiB,
          rttP50Ms: result.metrics.latency.p50Ms,
          rttP95Ms: result.metrics.latency.p95Ms,
          analysisFailures: analysis.failures,
        }));
      } finally {
        clients.shutdown();
      }
    }
  }

  // Swift CLI mirror (network writer path) when binary available
  if (!skipSwift) {
    // Mint auth for Swift the same way live contracts do (admin.createToken).
    const { init: initAdmin } = await import("@instantdb/admin");
    const admin = initAdmin({
      appId,
      adminToken,
      apiURI: process.env.INSTANT_API_URI ?? "https://api.instantdb.com",
    });
    const refreshToken = await admin.auth.createToken({
      email: `exercise-gem-swift-${runId.slice(0, 8)}@knophy.test`,
    });
    const user = await admin.auth.verifyToken(refreshToken);
    const swiftResult = await maybeRunSwift({
      appId,
      adminToken,
      refreshToken,
      userId: user?.id ?? "",
      runId,
      outDir,
      durationSeconds,
      maxAppRssMiB,
    });
    if (swiftResult) {
      report.suites["swift:simple"] = swiftResult;
    }
  }

  // Cross-side compare when both present
  const tsSimple = report.suites["typescript:simple"] as any;
  const swiftSimple = report.suites["swift:simple"] as any;
  if (tsSimple?.result?.metrics && swiftSimple?.metrics) {
    report.compare = compareMetrics(tsSimple.result.metrics, swiftSimple.metrics, "simple");
  }

  writeFileSync(join(outDir, "report.json"), `${JSON.stringify(report, null, 2)}\n`);
  writeFileSync(join(outDir, "report.summary.txt"), humanSummary(report));
  console.log(JSON.stringify({
    event: "exercise-gem-complete",
    outDir,
    reportPath: join(outDir, "report.json"),
    summaryPath: join(outDir, "report.summary.txt"),
    suiteKeys: Object.keys(report.suites),
  }, null, 2));
}

async function runSuite(
  suite: SuiteName,
  clients: Awaited<ReturnType<typeof openGemClients>>,
  options: Parameters<typeof runSimpleWrites>[1],
): Promise<ScenarioResult> {
  switch (suite) {
    case "simple":
    case "speed":
    case "memory-cap":
    case "bandwidth-cap":
    case "cpu-cap":
      return runSimpleWrites(clients, options);
    case "complex":
      return runComplexWrites(clients, options);
    default:
      throw new Error(`Unknown suite ${suite}`);
  }
}

function suiteDuration(suite: SuiteName, base: number): number {
  // Caps need a bit more wall time to hit the throttle steady state.
  if (suite === "speed") return Math.max(base, 20);
  if (suite.endsWith("-cap")) return Math.max(base, 20);
  return base;
}

function capsFor(suite: SuiteName, maxAppRssMiB: number): CapOptions | undefined {
  switch (suite) {
    case "memory-cap":
      return { maxAppRssMiB };
    case "bandwidth-cap":
      return { maxBytesPerSecond: 256_000 }; // ~0.25 MiB/s app payload
    case "cpu-cap":
      return { maxCpuPercent: 40 };
    case "speed":
      return undefined; // uncapped max throughput
    default:
      return undefined;
  }
}

async function persistWriteEvents(
  clients: Awaited<ReturnType<typeof openGemClients>>,
  events: WriteEventRecord[],
): Promise<void> {
  // Batch in chunks to avoid huge single transactions
  const { db, identity } = clients;
  const chunkSize = 25;
  for (let i = 0; i < events.length; i += chunkSize) {
    const slice = events.slice(i, i + chunkSize);
    const txs = slice.map((e) =>
      db.tx.writeEvents[e.eventId].update({
        runId: identity.runId,
        eventId: e.eventId,
        suite: e.suite,
        side: e.side,
        op: e.op,
        entityKind: e.entityKind,
        entityId: e.entityId,
        seq: e.seq,
        clientId: e.clientId,
        descriptor: e.descriptor,
        sentAtMs: e.sentAtMs,
        localAckAtMs: e.localAckAtMs ?? 0,
        observedAtMs: e.observedAtMs ?? 0,
        rttMs: e.rttMs ?? -1,
        payloadBytes: e.payloadBytes,
        metaJSON: JSON.stringify(e.meta ?? {}),
      }),
    );
    try {
      await db.transact(txs);
    } catch (err) {
      console.error("[gem] persistWriteEvents failed", err);
    }
  }
}

async function maybeRunSwift(input: {
  appId: string;
  adminToken: string;
  refreshToken: string;
  userId: string;
  runId: string;
  outDir: string;
  durationSeconds: number;
  maxAppRssMiB: number;
}): Promise<unknown | null> {
  const swiftRoot = resolve(gemRoot, "swift-cli");
  const packageSwift = join(swiftRoot, "Package.swift");
  if (!existsSync(packageSwift)) {
    console.log(JSON.stringify({
      event: "swift-skip",
      reason: "swift-cli Package.swift missing",
    }));
    return null;
  }

  const swiftDir = join(input.outDir, "swift");
  mkdirSync(swiftDir, { recursive: true });
  const resultPath = join(swiftDir, "swift-result.json");

  // Build + run ExerciseGem executable
  const build = spawn("swift", ["build", "--package-path", swiftRoot, "-c", "release"], {
    stdio: ["ignore", "pipe", "pipe"],
  });
  const buildOut = await collectProcess(build);
  writeFileSync(join(swiftDir, "swift-build.log"), buildOut.stdout + "\n" + buildOut.stderr);
  if (buildOut.code !== 0) {
    console.log(JSON.stringify({
      event: "swift-build-failed",
      code: buildOut.code,
      stderr: buildOut.stderr.slice(-2000),
    }));
    return {
      ok: false,
      error: "swift build failed",
      log: join(swiftDir, "swift-build.log"),
    };
  }

  const bin = join(swiftRoot, ".build", "release", "ExerciseGem");
  if (!input.refreshToken || !input.userId) {
    return { ok: false, error: "missing refreshToken/userId for Swift lane" };
  }
  const child = spawn(bin, [
    "--app-id", input.appId,
    "--refresh-token", input.refreshToken,
    "--user-id", input.userId,
    "--run-id", input.runId,
    "--duration", String(Math.min(input.durationSeconds, 20)),
    "--max-app-rss-mib", String(input.maxAppRssMiB),
    "--out", resultPath,
  ], {
    env: {
      ...process.env,
      INSTANT_APP_ID: input.appId,
      INSTANT_ADMIN_TOKEN: input.adminToken,
      INSTANT_SWIFT_DATA_BENCH_REFRESH_TOKEN: input.refreshToken,
      INSTANT_SWIFT_DATA_BENCH_USER_ID: input.userId,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  const runOut = await collectProcess(child, 120_000);
  writeFileSync(join(swiftDir, "swift-run.log"), runOut.stdout + "\n" + runOut.stderr);
  if (existsSync(resultPath)) {
    return JSON.parse(readFileSync(resultPath, "utf8"));
  }
  return {
    ok: false,
    error: "swift result missing",
    code: runOut.code,
    stdout: runOut.stdout.slice(-2000),
    stderr: runOut.stderr.slice(-2000),
  };
}

function collectProcess(
  child: ReturnType<typeof spawn>,
  timeoutMs = 600_000,
): Promise<{ code: number | null; stdout: string; stderr: string }> {
  return new Promise((resolvePromise) => {
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
    }, timeoutMs);
    child.stdout?.setEncoding("utf8");
    child.stderr?.setEncoding("utf8");
    child.stdout?.on("data", (c) => { stdout += c; });
    child.stderr?.on("data", (c) => { stderr += c; });
    child.on("close", (code) => {
      clearTimeout(timer);
      resolvePromise({ code, stdout, stderr });
    });
  });
}

function compareMetrics(ts: any, swift: any, label: string) {
  const tsObs = ts.throughput?.observedPerSecond ?? 0;
  const swObs = swift.throughput?.observedPerSecond ?? 0;
  const tsMem = ts.peakAppAttributedRssMiB ?? ts.peakRssMiB ?? 0;
  const swMem = swift.peakAppAttributedRssMiB ?? swift.peakRssMiB ?? 0;
  const tsP50 = ts.latency?.p50Ms ?? 0;
  const swP50 = swift.latency?.p50Ms ?? 0;
  return {
    label,
    typescript: { observedPerSecond: tsObs, peakAppRssMiB: tsMem, rttP50Ms: tsP50 },
    swift: { observedPerSecond: swObs, peakAppRssMiB: swMem, rttP50Ms: swP50 },
    ratios: {
      throughputSwiftOverTs: tsObs > 0 ? swObs / tsObs : null,
      memorySwiftOverTs: tsMem > 0 ? swMem / tsMem : null,
      latencySwiftOverTs: tsP50 > 0 ? swP50 / tsP50 : null,
    },
  };
}

function runCompare(tsPath: string | null, swiftPath: string | null): void {
  if (!tsPath || !swiftPath) {
    console.error("Usage: --suite compare --ts-result path --swift-result path");
    process.exit(1);
  }
  const ts = JSON.parse(readFileSync(tsPath, "utf8"));
  const sw = JSON.parse(readFileSync(swiftPath, "utf8"));
  const tsMetrics = ts.result?.metrics ?? ts.metrics ?? ts;
  const swMetrics = sw.result?.metrics ?? sw.metrics ?? sw;
  console.log(JSON.stringify(compareMetrics(tsMetrics, swMetrics, "compare"), null, 2));
}

function stripHuge(result: ScenarioResult): any {
  const { writeEvents, metrics, ...rest } = result;
  return {
    ...rest,
    writeEventCount: writeEvents.length,
    metrics: {
      ...metrics,
      samples: metrics.samples?.length ?? 0,
      // keep last sample only
      lastSample: metrics.lastSample,
      samplesOmitted: true,
    },
    writeEventsSample: writeEvents.slice(0, 5),
  };
}

function humanSummary(report: any): string {
  const lines: string[] = [];
  lines.push(`Instant Exercise Gem Report`);
  lines.push(`runId: ${report.runId}`);
  lines.push(`created: ${report.createdAt}`);
  lines.push(`durationSeconds: ${report.durationSeconds}`);
  lines.push(`maxAppRssMiB: ${report.maxAppRssMiB}`);
  lines.push("");
  for (const [key, value] of Object.entries(report.suites as Record<string, any>)) {
    const r = value?.result ?? value;
    const a = value?.analysis;
    const m = r?.metrics ?? value?.metrics;
    lines.push(`## ${key}`);
    lines.push(`  ok: ${r?.ok ?? value?.ok}`);
    if (m?.throughput) {
      lines.push(`  observed/s: ${m.throughput.observedPerSecond?.toFixed?.(2) ?? m.throughput.observedPerSecond}`);
      lines.push(`  localAck/s: ${m.throughput.localAckPerSecond?.toFixed?.(2) ?? m.throughput.localAckPerSecond}`);
      lines.push(`  writesObserved: ${m.throughput.writesObserved}`);
    }
    if (m?.latency) {
      lines.push(`  rtt p50/p95/p99 ms: ${m.latency.p50Ms}/${m.latency.p95Ms}/${m.latency.p99Ms}`);
    }
    if (m) {
      lines.push(
        `  peak app RSS MiB (excl node baseline): ${
          m.peakAppAttributedRssMiB?.toFixed?.(2) ?? m.peakAppAttributedRssMiB
        }`,
      );
      lines.push(`  peak process RSS MiB: ${m.peakRssMiB?.toFixed?.(2) ?? m.peakRssMiB}`);
    }
    if (a) {
      lines.push(`  analysis.ok: ${a.ok}`);
      if (a.failures?.length) lines.push(`  failures: ${a.failures.join(" | ")}`);
    }
    lines.push("");
  }
  if (report.compare) {
    lines.push("## compare");
    lines.push(JSON.stringify(report.compare, null, 2));
  }
  lines.push("");
  lines.push(`Note: Docker Instant self-host was not available on this host.`);
  lines.push(`Message/tx analysis used client WebSocket log + admin query ground truth.`);
  return lines.join("\n");
}

function flagValue(name: string): string | null {
  const idx = process.argv.indexOf(name);
  if (idx === -1) return null;
  return process.argv[idx + 1] ?? null;
}

function hasFlag(name: string): boolean {
  return process.argv.includes(name);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
