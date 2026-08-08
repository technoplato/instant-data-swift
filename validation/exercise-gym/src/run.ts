#!/usr/bin/env node
/**
 * Instant exercise gym orchestrator.
 *
 * Suites:
 *   simple | complex | speed | memory-cap | bandwidth-cap | cpu-cap | all
 *   analyze-only (re-analyze last artifact dir)
 *   compare (TS vs Swift result JSON)
 *
 * Env:
 *   INSTANT_APP_ID, INSTANT_ADMIN_TOKEN (or SCRIBE_TEST_*)
 *   EXERCISE_GYM_DURATION_SECONDS (default 15 for quick, 60 for full)
 *   EXERCISE_GYM_MAX_APP_RSS_MIB (default 150)
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
    ?? process.env.EXERCISE_GYM_DURATION_SECONDS
    ?? "15",
);
const maxAppRssMiB = Number(
  flagValue("--max-app-rss-mib")
    ?? process.env.EXERCISE_GYM_MAX_APP_RSS_MIB
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

  const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
  const selfHost = /localhost|127\.0\.0\.1/.test(apiURI);
  console.log(JSON.stringify({
    event: "exercise-gym-start",
    runId,
    suites,
    durationSeconds,
    maxAppRssMiB,
    outDir,
    apiURI,
    docker: selfHost ? "self-host-or-local-api" : "cloud",
    note: selfHost
      ? "Self-host Instant API; server logs + postgres samples collected when docker compose is up."
      : "Cloud Instant; client wire log + admin ground truth. Use EXERCISE_GYM_SELF_HOST=1 for Docker.",
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
      console.log(`[gym] TS suite=${suite} duration=${durationSeconds}s`);
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
    const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
    const websocketURI =
      process.env.INSTANT_WEBSOCKET_URI ?? "wss://api.instantdb.com/runtime/session";
    // Mint auth for Swift the same way live contracts do (admin.createToken).
    const { init: initAdmin } = await import("@instantdb/admin");
    const admin = initAdmin({
      appId,
      adminToken,
      apiURI,
    });
    const refreshToken = await admin.auth.createToken({
      email: `exercise-gym-swift-${runId.slice(0, 8)}@knophy.test`,
    });
    const user = await admin.auth.verifyToken(refreshToken);
    const swiftSuites: Array<"simple" | "complex"> =
      suiteArg === "complex"
        ? ["complex"]
        : suiteArg === "simple" || suiteArg === "all" || suiteArg === "speed"
          ? suiteArg === "all"
            ? ["simple", "complex"]
            : ["simple"]
          : ["simple", "complex"];
    // When suite is a cap suite only, still run simple+complex for parity if all; else simple.
    const swiftToRun: Array<"simple" | "complex"> =
      suiteArg === "all"
        ? ["simple", "complex"]
        : suiteArg === "complex"
          ? ["complex"]
          : ["simple"];
    void swiftSuites;
    for (const swiftSuite of swiftToRun) {
      const swiftResult = await maybeRunSwift({
        appId,
        adminToken,
        refreshToken,
        userId: user?.id ?? "",
        runId,
        outDir,
        durationSeconds,
        maxAppRssMiB,
        suite: swiftSuite,
        apiURI,
        websocketURI,
      });
      if (swiftResult) {
        report.suites[`swift:${swiftSuite}`] = swiftResult;
      }
    }
  }

  // Server-side artifacts from Docker self-host (when available)
  report.serverArtifacts = await collectServerArtifacts(outDir);

  // Cross-side compare when both present
  const tsSimple = report.suites["typescript:simple"] as any;
  const swiftSimple = report.suites["swift:simple"] as any;
  if (tsSimple?.result?.metrics && swiftSimple?.metrics) {
    report.compare = {
      ...(report.compare as object ?? {}),
      simple: compareMetrics(tsSimple.result.metrics, swiftSimple.metrics, "simple"),
    };
  }
  const tsComplex = report.suites["typescript:complex"] as any;
  const swiftComplex = report.suites["swift:complex"] as any;
  if (tsComplex?.result?.metrics && swiftComplex?.metrics) {
    report.compare = {
      ...(report.compare as object ?? {}),
      complex: compareMetrics(tsComplex.result.metrics, swiftComplex.metrics, "complex"),
    };
  }

  writeFileSync(join(outDir, "report.json"), `${JSON.stringify(report, null, 2)}\n`);
  writeFileSync(join(outDir, "report.summary.txt"), humanSummary(report));
  console.log(JSON.stringify({
    event: "exercise-gym-complete",
    outDir,
    reportPath: join(outDir, "report.json"),
    summaryPath: join(outDir, "report.summary.txt"),
    suiteKeys: Object.keys(report.suites),
    serverArtifacts: report.serverArtifacts,
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
      console.error("[gym] persistWriteEvents failed", err);
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
  suite: "simple" | "complex";
  apiURI: string;
  websocketURI: string;
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

  const swiftDir = join(input.outDir, "swift", input.suite);
  mkdirSync(swiftDir, { recursive: true });
  const resultPath = join(swiftDir, "swift-result.json");
  const bin = join(swiftRoot, ".build", "release", "ExerciseGym");

  // Build once if missing or package changed
  if (!existsSync(bin) || process.env.EXERCISE_GYM_FORCE_SWIFT_BUILD === "1") {
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
  } else {
    // still ensure binary exists after prior build
    if (!existsSync(bin)) {
      const build = spawn("swift", ["build", "--package-path", swiftRoot, "-c", "release"], {
        stdio: ["ignore", "pipe", "pipe"],
      });
      const buildOut = await collectProcess(build);
      writeFileSync(join(swiftDir, "swift-build.log"), buildOut.stdout + "\n" + buildOut.stderr);
      if (buildOut.code !== 0) {
        return { ok: false, error: "swift build failed", log: join(swiftDir, "swift-build.log") };
      }
    }
  }

  if (!input.refreshToken || !input.userId) {
    return { ok: false, error: "missing refreshToken/userId for Swift lane" };
  }
  console.log(JSON.stringify({ event: "swift-suite-start", suite: input.suite }));
  const child = spawn(bin, [
    "--suite", input.suite,
    "--app-id", input.appId,
    "--refresh-token", input.refreshToken,
    "--user-id", input.userId,
    "--run-id", input.runId,
    "--duration", String(Math.min(input.durationSeconds, 20)),
    "--max-app-rss-mib", String(input.maxAppRssMiB),
    "--api-uri", input.apiURI,
    "--websocket-uri", input.websocketURI,
    "--out", resultPath,
  ], {
    env: {
      ...process.env,
      INSTANT_APP_ID: input.appId,
      INSTANT_ADMIN_TOKEN: input.adminToken,
      INSTANT_API_URI: input.apiURI,
      INSTANT_WEBSOCKET_URI: input.websocketURI,
      INSTANT_SWIFT_DATA_BENCH_REFRESH_TOKEN: input.refreshToken,
      INSTANT_SWIFT_DATA_BENCH_USER_ID: input.userId,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  const runOut = await collectProcess(child, 180_000);
  writeFileSync(join(swiftDir, "swift-run.log"), runOut.stdout + "\n" + runOut.stderr);
  if (existsSync(resultPath)) {
    const parsed = JSON.parse(readFileSync(resultPath, "utf8"));
    console.log(JSON.stringify({
      event: "swift-suite-complete",
      suite: input.suite,
      ok: parsed.ok,
      observedPerSecond: parsed.metrics?.throughput?.observedPerSecond,
      rttP50Ms: parsed.metrics?.latency?.p50Ms,
      peakAppRssMiB: parsed.metrics?.peakAppAttributedRssMiB,
    }));
    return parsed;
  }
  return {
    ok: false,
    error: "swift result missing",
    code: runOut.code,
    stdout: runOut.stdout.slice(-2000),
    stderr: runOut.stderr.slice(-2000),
  };
}

/** Pull Docker Instant server logs + postgres transaction samples when self-host is up. */
async function collectServerArtifacts(outDir: string): Promise<Record<string, unknown>> {
  const serverDir = join(outDir, "server");
  mkdirSync(serverDir, { recursive: true });
  const composeDir = resolve(gemRoot, "docker");
  const result: Record<string, unknown> = {
    docker: false,
    health: null,
    logsPath: null,
    postgresDumpPath: null,
  };

  // Health against configured API
  const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
  try {
    const healthURL = `${apiURI.replace(/\/$/, "")}/health/system`;
    const res = await fetch(healthURL, { signal: AbortSignal.timeout(5_000) });
    const body = await res.text();
    result.health = { url: healthURL, status: res.status, body: body.slice(0, 500) };
    writeFileSync(join(serverDir, "health.json"), `${JSON.stringify(result.health, null, 2)}\n`);
  } catch (err) {
    result.health = { error: err instanceof Error ? err.message : String(err) };
  }

  // Docker compose logs if project is running
  try {
    const ps = spawn(
      "docker",
      ["compose", "--env-file", ".env", "ps", "--format", "json"],
      { cwd: composeDir, stdio: ["ignore", "pipe", "pipe"] },
    );
    const psOut = await collectProcess(ps, 15_000);
    if (psOut.code === 0 && psOut.stdout.trim()) {
      result.docker = true;
      writeFileSync(join(serverDir, "compose-ps.json"), psOut.stdout);
      const logs = spawn(
        "docker",
        ["compose", "--env-file", ".env", "logs", "--no-color", "--tail", "5000", "server"],
        { cwd: composeDir, stdio: ["ignore", "pipe", "pipe"] },
      );
      const logOut = await collectProcess(logs, 30_000);
      const logsPath = join(serverDir, "server.logs.txt");
      writeFileSync(logsPath, logOut.stdout + "\n" + logOut.stderr);
      result.logsPath = logsPath;

      // Extract magic-code / tx-ish lines for analysis
      const lines = (logOut.stdout + "\n" + logOut.stderr).split("\n");
      const interesting = lines.filter((l) =>
        /transact|tx|mutation|error|denied|permission|magic|code|client/i.test(l)
      );
      writeFileSync(
        join(serverDir, "server.interesting-lines.txt"),
        interesting.slice(-2000).join("\n") + "\n",
      );
      result.interestingLineCount = interesting.length;
    }
  } catch (err) {
    result.dockerError = err instanceof Error ? err.message : String(err);
  }

  // Postgres sample of recent triples / transactions when local docker postgres is up
  try {
    const pg = spawn(
      "docker",
      [
        "compose",
        "--env-file",
        ".env",
        "exec",
        "-T",
        "postgres",
        "psql",
        "-U",
        "instant",
        "-d",
        "instant",
        "-c",
        "\\dt",
      ],
      { cwd: composeDir, stdio: ["ignore", "pipe", "pipe"] },
    );
    const pgOut = await collectProcess(pg, 15_000);
    if (pgOut.code === 0) {
      writeFileSync(join(serverDir, "postgres-tables.txt"), pgOut.stdout);
      // Best-effort: dump recent rows from common Instant tables if they exist
      const dump = spawn(
        "docker",
        [
          "compose",
          "--env-file",
          ".env",
          "exec",
          "-T",
          "postgres",
          "psql",
          "-U",
          "instant",
          "-d",
          "instant",
          "-c",
          `SELECT table_name FROM information_schema.tables
           WHERE table_schema='public' ORDER BY 1 LIMIT 100;`,
        ],
        { cwd: composeDir, stdio: ["ignore", "pipe", "pipe"] },
      );
      const dumpOut = await collectProcess(dump, 15_000);
      writeFileSync(join(serverDir, "postgres-public-tables.txt"), dumpOut.stdout);
      result.postgresDumpPath = join(serverDir, "postgres-public-tables.txt");
    }
  } catch (err) {
    result.postgresError = err instanceof Error ? err.message : String(err);
  }

  writeFileSync(join(serverDir, "server-artifacts.json"), `${JSON.stringify(result, null, 2)}\n`);
  return result;
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
  lines.push(`Instant Exercise Gym Report`);
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
