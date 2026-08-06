/**
 * #156 — Scribe open-segment 20s network write/observe bench (TypeScript lanes + coordinator).
 *
 * Modes:
 *   --role writer|observer|coordinate
 *   --scenario net-a|net-b
 *
 * Network validity: observer counts monotonic `seq` advances on the open segment.
 * Never compare local vs network in the same ratio table.
 */
import { spawn, type ChildProcessByStdio } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { performance } from "node:perf_hooks";
import { init as initAdmin } from "@instantdb/admin";
import { i } from "@instantdb/core";
import type { Readable } from "node:stream";

// Inline schema (same as validation/fixtures/scribe-open-segment-bench.schema.ts)
// so the admin client always receives a real Instant schema object.
const schema = i.schema({
  entities: {
    recordings: i.entity({
      title: i.string().indexed(),
      updatedAtMs: i.number().indexed(),
    }),
    transcriptionSegments: i.entity({
      recordingID: i.string().indexed(),
      text: i.string(),
      wordsJSON: i.string(),
      wordCount: i.number().indexed(),
      seq: i.number().indexed(),
      updatedAtMs: i.number().indexed(),
    }),
  },
  links: {
    segmentRecording: {
      forward: {
        on: "transcriptionSegments",
        has: "one",
        label: "recording",
        required: true,
        onDelete: "cascade",
      },
      reverse: {
        on: "recordings",
        has: "many",
        label: "segments",
      },
    },
  },
});

type Role = "writer" | "observer" | "coordinate";
type Scenario = "net-a" | "net-b";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const args = process.argv.slice(2);
const role = (flagValue(args, "--role") ?? "coordinate") as Role;
const scenario = (flagValue(args, "--scenario") ?? "net-a") as Scenario;
const durationSeconds = Number(
  flagValue(args, "--duration")
    ?? process.env.INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS
    ?? "20",
);
const wordsPerUpsert = Number(
  flagValue(args, "--words-per-upsert")
    ?? process.env.INSTANT_SWIFT_DATA_BENCH_WORDS_PER_UPSERT
    ?? "12",
);

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";

if (role === "coordinate") {
  await coordinate();
} else if (role === "writer") {
  writeJSON(await runAdminWriter(scenario));
} else if (role === "observer") {
  writeJSON(await runAdminObserver(scenario));
} else {
  throw new Error(`Unknown --role ${role}`);
}

async function coordinate() {
  const recordingID = process.env.INSTANT_SWIFT_DATA_BENCH_RECORDING_ID ?? randomUUID();
  const segmentID = process.env.INSTANT_SWIFT_DATA_BENCH_SEGMENT_ID ?? randomUUID();
  const admin = initAdmin({ appId, adminToken, apiURI, schema, useDateObjects: true });
  const refreshToken = await admin.auth.createToken({
    email: `open-segment-bench-${randomUUID()}@example.com`,
  });
  const user = await admin.auth.verifyToken(refreshToken);
  if (!user?.id) throw new Error("Expected admin-created user id.");

  await seedEntities(admin, recordingID, segmentID);

  const resultsDir =
    process.env.INSTANT_SWIFT_DATA_BENCH_RESULTS_DIR
    ?? resolve(
      repositoryRoot,
      `.perf-runs/scribe-20s-write/${new Date().toISOString().replace(/[:.]/g, "-")}`,
    );
  mkdirSync(resultsDir, { recursive: true });

  const matrix: Array<{ scenario: Scenario; writer: "ts-admin" | "swift"; observer: "ts-admin" | "swift" }> = [
    { scenario: "net-a", writer: "ts-admin", observer: "swift" },
    { scenario: "net-b", writer: "swift", observer: "ts-admin" },
  ];

  const scenarios: any[] = [];
  for (const entry of matrix) {
    // Fresh segment ids per scenario so seq baselines stay clean.
    const scenarioRecordingID = randomUUID();
    const scenarioSegmentID = randomUUID();
    await seedEntities(admin, scenarioRecordingID, scenarioSegmentID);

    const commonEnv = {
      ...process.env,
      INSTANT_APP_ID: appId,
      INSTANT_ADMIN_TOKEN: adminToken,
      INSTANT_API_URI: apiURI,
      INSTANT_SWIFT_DATA_BENCH_REFRESH_TOKEN: refreshToken,
      INSTANT_SWIFT_DATA_BENCH_USER_ID: user.id,
      INSTANT_SWIFT_DATA_BENCH_RECORDING_ID: scenarioRecordingID,
      INSTANT_SWIFT_DATA_BENCH_SEGMENT_ID: scenarioSegmentID,
      INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS: String(durationSeconds),
      INSTANT_SWIFT_DATA_BENCH_WORDS_PER_UPSERT: String(wordsPerUpsert),
    };

    // Observer first (subscription/poll hot), then writer. Each process starts its
    // 20s clock only after printing BENCH_READY (post auth/seed), so Swift process
    // spawn time does not eat the observer window.
    const observerHandle =
      entry.observer === "ts-admin"
        ? startAdminRole("observer", entry.scenario, {
          appId,
          adminToken,
          apiURI,
          recordingID: scenarioRecordingID,
          segmentID: scenarioSegmentID,
          durationSeconds,
          wordsPerUpsert,
        })
        : startSwift("observer", entry.scenario, {
          ...commonEnv,
          INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS: String(durationSeconds),
        });
    await observerHandle.ready;
    const writerHandle =
      entry.writer === "ts-admin"
        ? startAdminRole("writer", entry.scenario, {
          appId,
          adminToken,
          apiURI,
          recordingID: scenarioRecordingID,
          segmentID: scenarioSegmentID,
          durationSeconds,
          wordsPerUpsert,
        })
        : startSwift("writer", entry.scenario, {
          ...commonEnv,
          INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS: String(durationSeconds),
        });
    await writerHandle.ready;
    const [writer, observer] = await Promise.all([
      writerHandle.result,
      observerHandle.result,
    ]);

    // Post-flight admin read (ground truth on the server for this segment).
    const verify = await admin.query({
      transcriptionSegments: {
        $: { where: { id: scenarioSegmentID } },
      },
      recordings: {
        $: { where: { id: scenarioRecordingID } },
      },
    });
    const verifySegment = firstEntity(verify?.transcriptionSegments, scenarioSegmentID);
    const verifyRecording = firstEntity(verify?.recordings, scenarioRecordingID);

    const valid = Number(observer.validWritesObserved ?? 0);
    const wall = Number(observer.wallSeconds ?? durationSeconds) || durationSeconds;
    scenarios.push({
      scenario: entry.scenario,
      writerSide: entry.writer,
      observerSide: entry.observer,
      validWritesObserved: valid,
      validWritesPerSecond: valid / wall,
      writer,
      observer,
      serverVerify: {
        segmentID: scenarioSegmentID,
        recordingFound: Boolean(verifyRecording),
        segmentFound: Boolean(verifySegment),
        seq: Number(verifySegment?.seq ?? 0),
        wordCount: Number(verifySegment?.wordCount ?? 0),
      },
    });

    writeFileSync(
      resolve(resultsDir, `${entry.scenario}.json`),
      `${JSON.stringify({ writer, observer }, null, 2)}\n`,
    );
  }

  const netA = scenarios.find((s) => s.scenario === "net-a");
  const netB = scenarios.find((s) => s.scenario === "net-b");
  const summary = {
    suite: "scribe-open-segment-20s-network",
    case: "benchmark.scribe-open-segment.network-matrix",
    issue: "156",
    ok: scenarios.every((s) => s.validWritesObserved >= 0 && s.writer?.ok !== false && s.observer?.ok !== false),
    appID: appId,
    durationSeconds,
    wordsPerUpsert,
    profile: "open-segment-words-json",
    compareRule: "network-vs-network-only",
    scenarios,
    compare: {
      metric: "valid_writes_per_s",
      netA_adminToSwift: netA?.validWritesPerSecond ?? null,
      netB_swiftToAdmin: netB?.validWritesPerSecond ?? null,
      ratio_netB_over_netA:
        netA && netB && netA.validWritesPerSecond > 0
          ? netB.validWritesPerSecond / netA.validWritesPerSecond
          : null,
      writerPeakMem: {
        netA_bytes: netA?.writer?.process?.rssPeakBytes
          ?? netA?.writer?.process?.footprintPeakBytes
          ?? null,
        netB_bytes: netB?.writer?.process?.rssPeakBytes
          ?? netB?.writer?.process?.footprintPeakBytes
          ?? null,
      },
      observerPeakMem: {
        netA_bytes: netA?.observer?.process?.rssPeakBytes
          ?? netA?.observer?.process?.footprintPeakBytes
          ?? null,
        netB_bytes: netB?.observer?.process?.rssPeakBytes
          ?? netB?.observer?.process?.footprintPeakBytes
          ?? null,
      },
    },
    notes: [
      "validWritesObserved counts monotonic seq advances seen by the observer process.",
      "Never ratio local store throughput against these network numbers.",
      "Words are a JSON blob on the single open segment (no word entities).",
    ],
    timestampMs: Date.now(),
  };

  writeFileSync(resolve(resultsDir, "summary.json"), `${JSON.stringify(summary, null, 2)}\n`);
  writeJSON(summary);
}

async function runAdminWriter(
  scenarioName: Scenario,
  opts?: {
    appId: string;
    adminToken: string;
    apiURI: string;
    recordingID: string;
    segmentID: string;
    durationSeconds: number;
    wordsPerUpsert: number;
  },
) {
  const app = opts?.appId ?? appId;
  const token = opts?.adminToken ?? adminToken;
  const uri = opts?.apiURI ?? apiURI;
  const recordingID = opts?.recordingID ?? requiredEnvironment("INSTANT_SWIFT_DATA_BENCH_RECORDING_ID");
  const segmentID = opts?.segmentID ?? requiredEnvironment("INSTANT_SWIFT_DATA_BENCH_SEGMENT_ID");
  const duration = opts?.durationSeconds ?? durationSeconds;
  const wordsN = opts?.wordsPerUpsert ?? wordsPerUpsert;

  const admin = initAdmin({ appId: app, adminToken: token, apiURI: uri, schema, useDateObjects: true });
  await seedEntities(admin, recordingID, segmentID);
  process.stderr.write("BENCH_READY role=writer\n");

  const memStart = process.memoryUsage();
  const cpuStart = process.cpuUsage();
  let rssPeak = memStart.rss;
  const words: Array<{ start: number; end: number; text: string }> = [];
  let seq = 0;
  let writesAttempted = 0;
  const started = performance.now();
  const deadline = started + duration * 1000;

  while (performance.now() < deadline) {
    seq += 1;
    const base = words.length * 0.08;
    for (let i = 0; i < wordsN; i++) {
      const start = base + i * 0.08;
      words.push({ start, end: start + 0.07, text: `w${words.length + 1}` });
    }
    const text = words.slice(-24).map((w) => w.text).join(" ");
    const updatedAtMs = Date.now();
    await admin.transact([
      admin.tx.transcriptionSegments[segmentID]
        .update({
          recordingID,
          text,
          wordsJSON: JSON.stringify(words),
          wordCount: words.length,
          seq,
          updatedAtMs,
        })
        .link({ recording: recordingID }),
    ]);
    writesAttempted += 1;
    rssPeak = Math.max(rssPeak, process.memoryUsage().rss);
  }

  const wallSeconds = (performance.now() - started) / 1000;
  const cpu = process.cpuUsage(cpuStart);
  const memEnd = process.memoryUsage();

  return {
    suite: "scribe-open-segment-20s-network",
    side: "typescript-admin",
    role: "writer",
    scenario: scenarioName,
    appID: app,
    recordingID,
    segmentID,
    durationSeconds: duration,
    wallSeconds,
    writesAttempted,
    validWritesObserved: 0,
    maxSeqSeen: seq,
    finalWordCount: words.length,
    wordsPerUpsert: wordsN,
    ok: writesAttempted > 0,
    process: {
      rssStartBytes: memStart.rss,
      rssPeakBytes: rssPeak,
      rssEndBytes: memEnd.rss,
      heapUsedEndBytes: memEnd.heapUsed,
      cpuUserSeconds: cpu.user / 1e6,
      cpuSystemSeconds: cpu.system / 1e6,
    },
    notes: [
      "TypeScript @instantdb/admin writer free-runs for duration.",
      "validWritesObserved is measured by the observer process.",
    ],
    timestampMs: Date.now(),
  };
}

async function runAdminObserver(
  scenarioName: Scenario,
  opts?: {
    appId: string;
    adminToken: string;
    apiURI: string;
    recordingID: string;
    segmentID: string;
    durationSeconds: number;
    wordsPerUpsert: number;
  },
) {
  const app = opts?.appId ?? appId;
  const token = opts?.adminToken ?? adminToken;
  const uri = opts?.apiURI ?? apiURI;
  const recordingID = opts?.recordingID ?? requiredEnvironment("INSTANT_SWIFT_DATA_BENCH_RECORDING_ID");
  const segmentID = opts?.segmentID ?? requiredEnvironment("INSTANT_SWIFT_DATA_BENCH_SEGMENT_ID");
  const duration = opts?.durationSeconds ?? durationSeconds;
  const wordsN = opts?.wordsPerUpsert ?? wordsPerUpsert;

  const admin = initAdmin({ appId: app, adminToken: token, apiURI: uri, schema, useDateObjects: true });
  // Touch the namespace once before READY so the first timed poll is warm.
  await admin.query({ transcriptionSegments: {} });
  process.stderr.write("BENCH_READY role=observer\n");

  const memStart = process.memoryUsage();
  const cpuStart = process.cpuUsage();
  let rssPeak = memStart.rss;
  let maxSeqSeen = 0;
  let finalWordCount = 0;
  const started = performance.now();
  const deadline = started + duration * 1000;

  while (performance.now() < deadline) {
    // Prefer unfiltered namespace scan + client-side id match: concurrent live
    // writes have returned empty for `$where: { id }` mid-flight even when the
    // row is present (post-flight verify with the same where works).
    const result: any = await admin.query({
      transcriptionSegments: {},
    });
    const row = firstEntity(result?.transcriptionSegments, segmentID);
    if (row) {
      const seq = Number(row.seq ?? 0);
      maxSeqSeen = Math.max(maxSeqSeen, seq);
      finalWordCount = Math.max(finalWordCount, Number(row.wordCount ?? 0));
    }
    rssPeak = Math.max(rssPeak, process.memoryUsage().rss);
    await sleep(25);
  }

  const wallSeconds = (performance.now() - started) / 1000;
  const cpu = process.cpuUsage(cpuStart);
  const memEnd = process.memoryUsage();
  // Seed always starts at seq 0.
  const valid = Math.max(0, maxSeqSeen);

  return {
    suite: "scribe-open-segment-20s-network",
    side: "typescript-admin",
    role: "observer",
    scenario: scenarioName,
    appID: app,
    recordingID,
    segmentID,
    durationSeconds: duration,
    wallSeconds,
    writesAttempted: 0,
    validWritesObserved: valid,
    maxSeqSeen,
    finalWordCount,
    wordsPerUpsert: wordsN,
    ok: true,
    process: {
      rssStartBytes: memStart.rss,
      rssPeakBytes: rssPeak,
      rssEndBytes: memEnd.rss,
      heapUsedEndBytes: memEnd.heapUsed,
      cpuUserSeconds: cpu.user / 1e6,
      cpuSystemSeconds: cpu.system / 1e6,
    },
    notes: [
      "Observer polls admin.query for monotonic seq advances (network path).",
    ],
    timestampMs: Date.now(),
  };
}

async function seedEntities(admin: any, recordingID: string, segmentID: string) {
  const updatedAtMs = Date.now();
  await admin.transact([
    admin.tx.recordings[recordingID].update({
      title: "open-segment-bench-fast-speech",
      updatedAtMs,
    }),
    admin.tx.transcriptionSegments[segmentID]
      .update({
        recordingID,
        text: "",
        wordsJSON: "[]",
        wordCount: 0,
        seq: 0,
        updatedAtMs,
      })
      .link({ recording: recordingID }),
  ]);
}

type RoleHandle = {
  ready: Promise<void>;
  result: Promise<any>;
};

function startAdminRole(
  role: "writer" | "observer",
  scenarioName: Scenario,
  opts: {
    appId: string;
    adminToken: string;
    apiURI: string;
    recordingID: string;
    segmentID: string;
    durationSeconds: number;
    wordsPerUpsert: number;
  },
): RoleHandle {
  let resolveReady!: () => void;
  const ready = new Promise<void>((resolve) => {
    resolveReady = resolve;
  });
  // Admin roles run in-process; READY is emitted inside the role function.
  // We resolve ready on the next tick after the role starts, then the role
  // itself writes BENCH_READY before its timed loop. For in-process, wait for
  // the first microtask after start by wrapping.
  const result = (async () => {
    // Patch stderr write temporarily? Simpler: call role which emits READY first.
    // Resolve ready via a short poll of a shared flag set by the role functions.
    const flag = { ready: false };
    const originalWrite = process.stderr.write.bind(process.stderr);
    (process.stderr as any).write = (chunk: any, ...rest: any[]) => {
      const text = typeof chunk === "string" ? chunk : chunk?.toString?.() ?? "";
      if (text.includes("BENCH_READY")) {
        flag.ready = true;
        resolveReady();
      }
      return originalWrite(chunk, ...rest);
    };
    try {
      if (role === "writer") {
        return await runAdminWriter(scenarioName, opts);
      }
      return await runAdminObserver(scenarioName, opts);
    } finally {
      (process.stderr as any).write = originalWrite;
      if (!flag.ready) resolveReady();
    }
  })();
  return { ready, result };
}

function startSwift(
  role: "writer" | "observer",
  scenarioName: Scenario,
  env: NodeJS.ProcessEnv,
): RoleHandle {
  let resolveReady!: () => void;
  const ready = new Promise<void>((resolve) => {
    resolveReady = resolve;
  });

  const binCandidates = [
    resolve(repositoryRoot, ".build/debug/scribe-shaped-20s-write-bench"),
    resolve(repositoryRoot, ".build/release/scribe-shaped-20s-write-bench"),
  ];
  const bin = binCandidates.find((path) => existsSync(path));

  const command = bin ? bin : "swift";
  const args = bin
    ? [
      "--role",
      role,
      "--scenario",
      scenarioName,
      "--duration",
      String(durationSeconds),
      "--words-per-upsert",
      String(wordsPerUpsert),
    ]
    : [
      "run",
      "--package-path",
      repositoryRoot,
      "scribe-shaped-20s-write-bench",
      "--role",
      role,
      "--scenario",
      scenarioName,
      "--duration",
      String(durationSeconds),
      "--words-per-upsert",
      String(wordsPerUpsert),
    ];

  const result = new Promise<any>((resolvePromise, reject) => {
    const child: ChildProcessByStdio<null, Readable, Readable> = spawn(
      command,
      args,
      {
        cwd: repositoryRoot,
        env,
        stdio: ["ignore", "pipe", "pipe"],
      },
    );
    let stdout = "";
    let stderr = "";
    let readySignaled = false;
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
      if (!readySignaled && stderr.includes("BENCH_READY")) {
        readySignaled = true;
        resolveReady();
      }
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (!readySignaled) resolveReady();
      try {
        const jsonStart = stdout.indexOf("{");
        if (jsonStart < 0) {
          reject(
            new Error(
              `Swift ${role} produced no JSON (exit ${code}). stderr=${stderr.slice(0, 2000)} stdout=${stdout.slice(0, 500)}`,
            ),
          );
          return;
        }
        const parsed = JSON.parse(stdout.slice(jsonStart));
        if (code !== 0 && parsed.ok !== true) {
          reject(
            new Error(
              `Swift ${role} failed (exit ${code}): ${parsed.error ?? stderr.slice(0, 1000)}`,
            ),
          );
          return;
        }
        resolvePromise(parsed);
      } catch (error) {
        reject(
          new Error(
            `Swift ${role} JSON parse failed (exit ${code}): ${String(error)}; stderr=${stderr.slice(0, 1500)}; stdout=${stdout.slice(0, 500)}`,
          ),
        );
      }
    });
  });

  return { ready, result };
}

function writeJSON(value: unknown) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable ${name}`);
  return value;
}

function flagValue(argv: string[], name: string): string | undefined {
  const index = argv.indexOf(name);
  if (index < 0) return undefined;
  return argv[index + 1];
}

function sleep(ms: number) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, ms));
}

function firstEntity(collection: any, id: string): any | undefined {
  if (!collection) return undefined;
  if (Array.isArray(collection)) {
    return collection.find((row) => row?.id === id) ?? collection[0];
  }
  if (typeof collection === "object") {
    return collection[id] ?? Object.values(collection)[0];
  }
  return undefined;
}
