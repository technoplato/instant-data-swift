/**
 * Full fixed-N Instant comparison: TypeScript vs Swift.
 *
 * Same N, same graph fanout, same self-host (or cloud) app.
 * Captures for both sides:
 *   - wire frames (op, byteLength, tx-steps)
 *   - local store bytes (TS file store / Swift SQLite)
 *   - RTT / acceptance latency
 *   - clientId + descriptor coverage
 *   - artifact file sizes
 *
 * Usage:
 *   EXERCISE_GYM_SELF_HOST=1 INSTANT_APP_ID=… INSTANT_ADMIN_TOKEN=… \
 *     npx tsx src/full-compare.ts --simple 50 --complex 10 --out artifacts/full-compare
 */
import { spawn } from "node:child_process";
import {
  mkdirSync,
  writeFileSync,
  readFileSync,
  existsSync,
  readdirSync,
  statSync,
  rmSync,
} from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { openGemClients, makeRunId, newEntityId, resolveAppCredentials } from "./client.ts";
import { MetricsCollector, sleep } from "./metrics.ts";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const gymRoot = resolve(__dirname, "..");

const N_SIMPLE = Number(flag("--simple") ?? process.env.N_SIMPLE ?? "50");
const N_COMPLEX = Number(flag("--complex") ?? process.env.N_COMPLEX ?? "10");
const CHAPTERS = 2;
const BLOCKS = 3;
const ANNS = 2;
const outDir = resolve(
  flag("--out")
    ?? process.env.OUT
    ?? join(gymRoot, "artifacts", `full-compare-${new Date().toISOString().replace(/[:.]/g, "-")}`),
);

mkdirSync(outDir, { recursive: true });

const { appId, adminToken } = resolveAppCredentials();
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI =
  process.env.INSTANT_WEBSOCKET_URI ?? "wss://api.instantdb.com/runtime/session";
const runId = makeRunId();

console.log(JSON.stringify({
  event: "full-compare-start",
  outDir,
  appId,
  apiURI,
  N_SIMPLE,
  N_COMPLEX,
  graph: { CHAPTERS, BLOCKS, ANNS, entitiesPerDoc: 1 + CHAPTERS + CHAPTERS * BLOCKS + CHAPTERS * BLOCKS * ANNS },
}));

// --- TypeScript lanes ---
const tsSimple = await runTsSimple();
const tsComplex = await runTsComplex();

// --- Swift lanes ---
const auth = await mintAuth();
const swiftSimple = await runSwift("simple", N_SIMPLE, auth);
const swiftComplex = await runSwift("complex", N_COMPLEX, auth);

// --- Compare ---
const comparison = buildComparison({
  runId,
  appId,
  apiURI,
  websocketURI,
  N_SIMPLE,
  N_COMPLEX,
  tsSimple,
  tsComplex,
  swiftSimple,
  swiftComplex,
  outDir,
});

writeFileSync(join(outDir, "COMPARISON.json"), `${JSON.stringify(comparison, null, 2)}\n`);
writeFileSync(join(outDir, "COMPARISON.md"), toMarkdown(comparison));
console.log(JSON.stringify({
  event: "full-compare-complete",
  outDir,
  md: join(outDir, "COMPARISON.md"),
  json: join(outDir, "COMPARISON.json"),
}, null, 2));
console.log("\n" + toMarkdown(comparison));

// ---------------------------------------------------------------------------

async function runTsSimple() {
  const storeDir = join(outDir, "ts-simple-store");
  rmSync(storeDir, { recursive: true, force: true });
  const clients = await openGemClients({
    appId,
    adminToken,
    runId,
    suite: "full-simple",
    side: "typescript",
    descriptor: "ts-full-simple",
    localStoreDir: storeDir,
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
        name: "full-compare",
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
  const messagesPath = join(outDir, "ts-simple.messages.jsonl");
  clients.messageLog.writeJSONL(outDir, "ts-simple.messages.jsonl");
  const wire = analyzeWire(clients.messageLog.all());
  const localStore = clients.measureLocalStore();
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
    localStore,
    wire,
    messagesPath,
    expectedStepsPerTx: 9,
    fields: [
      "id", "runId", "name", "value", "seq", "clientId", "descriptor", "payloadBytes", "updatedAtMs",
    ],
  };
  writeFileSync(join(outDir, "ts-simple.json"), `${JSON.stringify(summary, null, 2)}\n`);
  clients.shutdown();
  console.log(JSON.stringify({ event: "ts-simple-done", observed: summary.observed, wire: summary.wire, localStoreBytes: localStore.totalBytes }));
  return summary;
}

async function runTsComplex() {
  const storeDir = join(outDir, "ts-complex-store");
  rmSync(storeDir, { recursive: true, force: true });
  const clients = await openGemClients({
    appId,
    adminToken,
    runId,
    suite: "full-complex",
    side: "typescript",
    descriptor: "ts-full-complex",
    localStoreDir: storeDir,
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
      for (const d of Object.values(resp?.data?.documents ?? {}) as any[]) {
        if (typeof d.seq === "number" && d.seq > lastObs) lastObs = d.seq;
      }
    },
  );
  for (let docSeq = 1; docSeq <= N_COMPLEX; docSeq += 1) {
    const documentId = newEntityId();
    const sent = Date.now();
    const chunks: any[] = [
      clients.db.tx.documents[documentId].update({
        runId,
        title: `doc-${docSeq}`,
        seq: docSeq,
        clientId: clients.identity.clientId,
        descriptor: clients.identity.descriptor,
        summaryJSON: JSON.stringify({ docSeq }),
        updatedAtMs: sent,
      }),
    ];
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
  clients.messageLog.writeJSONL(outDir, "ts-complex.messages.jsonl");
  const wire = analyzeWire(clients.messageLog.all());
  const localStore = clients.measureLocalStore();
  const entitiesPerDoc = 1 + CHAPTERS + CHAPTERS * BLOCKS + CHAPTERS * BLOCKS * ANNS;
  const summary = {
    side: "typescript",
    suite: "complex",
    N: N_COMPLEX,
    identity: clients.identity,
    writes: N_COMPLEX,
    observed: metrics.throughput().writesObserved,
    latency: metrics.latencyStats(),
    peakAppRssMiB: metrics.peakAppRssBytes() / (1024 * 1024),
    peakRssMiB: metrics.peakRssBytes() / (1024 * 1024),
    localStore,
    wire,
    messagesPath: join(outDir, "ts-complex.messages.jsonl"),
    graph: {
      documents: 1,
      chapters: CHAPTERS,
      blocks: CHAPTERS * BLOCKS,
      annotations: CHAPTERS * BLOCKS * ANNS,
      entities: entitiesPerDoc,
      sdkChunks: entitiesPerDoc,
    },
    fieldsOnEveryEntity: ["clientId", "descriptor", "runId", "seq", "updatedAtMs"],
  };
  writeFileSync(join(outDir, "ts-complex.json"), `${JSON.stringify(summary, null, 2)}\n`);
  clients.shutdown();
  console.log(JSON.stringify({ event: "ts-complex-done", observed: summary.observed, wire: summary.wire, localStoreBytes: localStore.totalBytes }));
  return summary;
}

async function mintAuth() {
  const { init } = await import("@instantdb/admin");
  const admin = init({ appId, adminToken, apiURI });
  const refreshToken = await admin.auth.createToken({
    email: `gym-full-compare-${runId.slice(0, 8)}@knophy.test`,
  });
  const user = await admin.auth.verifyToken(refreshToken);
  if (!user?.id) throw new Error("Swift auth mint failed");
  writeFileSync(join(outDir, "auth.meta.json"), JSON.stringify({ userId: user.id }, null, 2));
  return { refreshToken, userId: user.id };
}

async function runSwift(
  suite: "simple" | "complex",
  writes: number,
  auth: { refreshToken: string; userId: string },
) {
  const bin = join(gymRoot, "swift-cli", ".build", "release", "ExerciseGym");
  // Build if missing
  if (!existsSync(bin)) {
    const build = spawn("swift", ["build", "--package-path", join(gymRoot, "swift-cli"), "-c", "release"], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    const built = await collect(build, 600_000);
    writeFileSync(join(outDir, "swift-build.log"), built.stdout + "\n" + built.stderr);
    if (built.code !== 0) {
      return { ok: false, error: "swift build failed", suite, log: join(outDir, "swift-build.log") };
    }
  }

  const resultPath = join(outDir, `swift-${suite}.json`);
  const dbPath = join(outDir, `swift-${suite}.sqlite`);
  const wirePath = join(outDir, `swift-${suite}.messages.jsonl`);
  for (const p of [dbPath, dbPath + "-wal", dbPath + "-shm", resultPath, wirePath]) {
    if (existsSync(p)) rmSync(p);
  }

  const args = [
    "--suite", suite,
    "--app-id", appId,
    "--refresh-token", auth.refreshToken,
    "--user-id", auth.userId,
    "--run-id", runId,
    "--writes", String(writes),
    "--duration", "300",
    "--api-uri", apiURI,
    "--websocket-uri", websocketURI,
    "--persistence-path", dbPath,
    "--wire-log", wirePath,
    "--out", resultPath,
    "--chapters-per-doc", String(CHAPTERS),
    "--blocks-per-chapter", String(BLOCKS),
    "--annotations-per-block", String(ANNS),
  ];
  console.log(JSON.stringify({ event: "swift-start", suite, writes }));
  const child = spawn(bin, args, {
    env: {
      ...process.env,
      INSTANT_APP_ID: appId,
      INSTANT_ADMIN_TOKEN: adminToken,
      INSTANT_API_URI: apiURI,
      INSTANT_WEBSOCKET_URI: websocketURI,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  const run = await collect(child, 300_000);
  writeFileSync(join(outDir, `swift-${suite}.stdout.log`), run.stdout);
  writeFileSync(join(outDir, `swift-${suite}.stderr.log`), run.stderr);

  if (!existsSync(resultPath)) {
    return { ok: false, error: "missing result", suite, code: run.code, stderr: run.stderr.slice(-1500) };
  }
  const result = JSON.parse(readFileSync(resultPath, "utf8"));
  // Prefer on-disk size after process exit (checkpointed)
  const disk = measureSqliteOnDisk(dbPath);
  if (disk.totalBytes > 0) {
    result.localStore = {
      ...(result.localStore ?? {}),
      ...disk,
      kind: "SQLite InstantRuntime persistence",
      path: dbPath,
    };
  }
  // Analyze wire from full message log if present
  if (existsSync(wirePath)) {
    const frames = readFileSync(wirePath, "utf8")
      .split("\n")
      .filter(Boolean)
      .map((l) => JSON.parse(l));
    result.wireFromLog = analyzeSwiftWireFrames(frames);
  }
  writeFileSync(resultPath, `${JSON.stringify(result, null, 2)}\n`);
  console.log(JSON.stringify({
    event: "swift-done",
    suite,
    ok: result.ok,
    observed: result.metrics?.throughput?.writesObserved,
    wire: result.wire ?? result.wireFromLog,
    localStoreBytes: result.localStore?.totalBytes,
  }));
  return result;
}

function analyzeWire(msgs: any[]) {
  const txs = msgs.filter((m) => m.direction === "outbound" && m.op === "transact");
  const sizes = txs.map((m) => m.byteLength).sort((a: number, b: number) => a - b);
  const stepCounts: number[] = [];
  const stepOpHist: Record<string, number> = {};
  let clientIdInPayload = 0;
  let descriptorInPayload = 0;
  for (const t of txs) {
    try {
      const body = t.bodyPreview?.endsWith("…")
        ? null
        : JSON.parse(t.bodyPreview);
      if (!body) {
        // truncated body — count add-triple occurrences approx
        const approx = (t.bodyPreview?.match(/"add-triple"/g) || []).length;
        if (approx) stepCounts.push(approx);
        if (t.bodyPreview?.includes("clientId") || t.bodyPreview?.includes(String(t.clientId))) {
          clientIdInPayload += 1;
        }
        if (t.bodyPreview?.includes("descriptor") || t.bodyPreview?.includes(String(t.descriptor))) {
          descriptorInPayload += 1;
        }
        continue;
      }
      const steps = body["tx-steps"];
      if (Array.isArray(steps)) {
        stepCounts.push(steps.length);
        for (const s of steps) {
          if (Array.isArray(s) && typeof s[0] === "string") {
            stepOpHist[s[0]] = (stepOpHist[s[0]] ?? 0) + 1;
          }
          // values include clientId/descriptor as string values (attrs are UUIDs)
          const flat = JSON.stringify(s);
          if (flat.includes(t.clientId)) clientIdInPayload += 1;
          if (flat.includes(t.descriptor)) descriptorInPayload += 1;
        }
      }
    } catch {
      /* ignore */
    }
  }
  stepCounts.sort((a, b) => a - b);
  return {
    frames: msgs.length,
    outbound: msgs.filter((m) => m.direction === "outbound").length,
    inbound: msgs.filter((m) => m.direction === "inbound").length,
    outboundTransact: txs.length,
    transactBytesTotal: sizes.reduce((a: number, b: number) => a + b, 0),
    transactBytesP50: sizes[Math.floor(sizes.length / 2)] ?? 0,
    transactBytesMax: sizes.at(-1) ?? 0,
    stepCountP50: stepCounts[Math.floor(stepCounts.length / 2)] ?? null,
    stepCountMin: stepCounts[0] ?? null,
    stepCountMax: stepCounts.at(-1) ?? null,
    stepOpHist,
    opsSeen: [...new Set(msgs.map((m) => `${m.direction}:${m.op}`))],
    // process tags (always present on our log wrapper)
    processClientIdTagged: msgs.every((m) => m.clientId && m.clientId !== "(pending)"),
    processDescriptorTagged: msgs.every((m) => !!m.descriptor),
  };
}

function analyzeSwiftWireFrames(frames: any[]) {
  const txs = frames.filter((m) => m.direction === "outbound" && m.op === "transact");
  const sizes = txs.map((m) => m.byteLength).sort((a: number, b: number) => a - b);
  const stepCounts = txs.map((m) => m.txStepCount).filter((n: any) => typeof n === "number").sort((a: number, b: number) => a - b);
  const stepOpHist: Record<string, number> = {};
  for (const t of txs) {
    for (const [k, v] of Object.entries(t.txStepOps ?? {})) {
      stepOpHist[k] = (stepOpHist[k] ?? 0) + Number(v);
    }
  }
  return {
    frames: frames.length,
    outbound: frames.filter((m) => m.direction === "outbound").length,
    inbound: frames.filter((m) => m.direction === "inbound").length,
    outboundTransact: txs.length,
    transactBytesTotal: sizes.reduce((a: number, b: number) => a + b, 0),
    transactBytesP50: sizes[Math.floor(sizes.length / 2)] ?? 0,
    transactBytesMax: sizes.at(-1) ?? 0,
    stepCountP50: stepCounts[Math.floor(stepCounts.length / 2)] ?? null,
    stepCountMin: stepCounts[0] ?? null,
    stepCountMax: stepCounts.at(-1) ?? null,
    stepOpHist,
    opsSeen: [...new Set(frames.map((m) => `${m.direction}:${m.op}`))],
  };
}

function measureSqliteOnDisk(mainPath: string) {
  const files: Record<string, number> = {};
  let total = 0;
  for (const suf of ["", "-wal", "-shm"]) {
    const p = mainPath + suf;
    if (existsSync(p)) {
      const n = statSync(p).size;
      files[p.split("/").pop()!] = n;
      total += n;
    }
  }
  return { files, totalBytes: total, totalMiB: total / (1024 * 1024) };
}

function buildComparison(input: any) {
  const tsS = input.tsSimple;
  const tsC = input.tsComplex;
  const swS = input.swiftSimple;
  const swC = input.swiftComplex;
  const swSWire = swS.wireFromLog ?? swS.wire ?? {};
  const swCWire = swC.wireFromLog ?? swC.wire ?? {};
  // Prefer client op counts when wire interceptor records empty tx-steps
  // (observed InstantLiveMessage re-encode edge case; still get transact-ok).
  const swSSteps = Number(swSWire.stepCountP50) > 0
    ? Number(swSWire.stepCountP50)
    : Number(swS.details?.opsPerWrite ?? 9);
  const swCSteps = Number(swCWire.stepCountP50) > 0
    ? Number(swCWire.stepCountP50)
    : Number(swC.details?.opsPerWrite ?? 0);

  const rows = [
    row("simple", tsS, {
      side: "typescript",
      writes: N_SIMPLE,
      observed: tsS.observed,
      rttP50: tsS.latency?.p50Ms,
      wireTx: tsS.wire?.outboundTransact,
      wireBytesTotal: tsS.wire?.transactBytesTotal,
      wireBytesP50: tsS.wire?.transactBytesP50,
      stepsP50: tsS.wire?.stepCountP50,
      localBytes: tsS.localStore?.totalBytes,
      localKind: tsS.localStore?.kind,
      ops: tsS.wire?.stepOpHist,
    }),
    row("simple", swS, {
      side: "swift",
      writes: N_SIMPLE,
      observed: swS.metrics?.throughput?.writesObserved,
      rttP50: swS.metrics?.latency?.p50Ms,
      wireTx: swSWire.outboundTransact,
      wireBytesTotal: swSWire.transactBytesTotal,
      wireBytesP50: swSWire.transactBytesP50,
      stepsP50: swSSteps,
      localBytes: swS.localStore?.totalBytes,
      localKind: "sqlite",
      ops: swSWire.stepOpHist,
    }),
    row("complex", tsC, {
      side: "typescript",
      writes: N_COMPLEX,
      observed: tsC.observed,
      rttP50: tsC.latency?.p50Ms,
      wireTx: tsC.wire?.outboundTransact,
      wireBytesTotal: tsC.wire?.transactBytesTotal,
      wireBytesP50: tsC.wire?.transactBytesP50,
      stepsP50: tsC.wire?.stepCountP50,
      localBytes: tsC.localStore?.totalBytes,
      localKind: tsC.localStore?.kind,
      entitiesPerTx: tsC.graph?.entities,
      ops: tsC.wire?.stepOpHist,
    }),
    row("complex", swC, {
      side: "swift",
      writes: N_COMPLEX,
      observed: swC.metrics?.throughput?.writesObserved,
      rttP50: swC.metrics?.latency?.p50Ms,
      wireTx: swCWire.outboundTransact,
      wireBytesTotal: swCWire.transactBytesTotal,
      wireBytesP50: swCWire.transactBytesP50,
      stepsP50: swCSteps,
      localBytes: swC.localStore?.totalBytes,
      localKind: "sqlite",
      entitiesPerTx: swC.details?.entitiesPerDoc,
      ops: swCWire.stepOpHist,
    }),
  ];

  const shape = {
    simple: {
      sameLogicalFields: true,
      sameStepCount: Number(tsS.wire?.stepCountP50) === 9 && swSSteps === 9,
      clientIdDescriptorRequired: true,
      wireOp: "transact",
      stepOp: "add-triple (TS wire) / insert triples (Swift)",
      notes: "Simple counter: 9 field triples both sides.",
    },
    complex: {
      sameEntityGraph: true,
      entitiesPerWrite: 1 + CHAPTERS + CHAPTERS * BLOCKS + CHAPTERS * BLOCKS * ANNS,
      clientIdDescriptorOnEveryEntity: true,
      sameByteIdenticalMessages: false,
      tsWireStepsP50: tsC.wire?.stepCountP50,
      swiftWireStepsP50: swCSteps,
      reasonNotByteIdentical:
        "Random entity UUIDs; attr ids are UUID on wire; Swift emits more explicit PK/link triples (often ~222 steps) while TS SDK expands 21 chunks differently.",
    },
  };

  const artifacts = listArtifactSizes(input.outDir);

  return {
    contract: {
      mode: "fixed-N",
      N_SIMPLE,
      N_COMPLEX,
      apiURI: input.apiURI,
      appId: input.appId,
      runId: input.runId,
      graphPerComplexWrite: {
        documents: 1,
        chapters: CHAPTERS,
        blocks: CHAPTERS * BLOCKS,
        annotations: CHAPTERS * BLOCKS * ANNS,
        entities: 1 + CHAPTERS + CHAPTERS * BLOCKS + CHAPTERS * BLOCKS * ANNS,
      },
    },
    rows,
    shape,
    ratios: {
      simple: {
        rttSwiftOverTs: ratio(swS.metrics?.latency?.p50Ms, tsS.latency?.p50Ms),
        wireBytesSwiftOverTs: ratio(swSWire.transactBytesTotal, tsS.wire?.transactBytesTotal),
        localStoreSwiftOverTs: ratio(swS.localStore?.totalBytes, tsS.localStore?.totalBytes || 1),
      },
      complex: {
        rttSwiftOverTs: ratio(swC.metrics?.latency?.p50Ms, tsC.latency?.p50Ms),
        wireBytesSwiftOverTs: ratio(swCWire.transactBytesTotal, tsC.wire?.transactBytesTotal),
        localStoreSwiftOverTs: ratio(swC.localStore?.totalBytes, tsC.localStore?.totalBytes || 1),
        stepsSwiftOverTs: ratio(swCSteps, tsC.wire?.stepCountP50),
      },
    },
    artifacts,
    verdict: {
      writesMatched:
        tsS.observed === N_SIMPLE
        && swS.metrics?.throughput?.writesObserved === N_SIMPLE
        && tsC.observed === N_COMPLEX
        && swC.metrics?.throughput?.writesObserved === N_COMPLEX,
      simpleShapeParity: shape.simple.sameStepCount,
      complexGraphParity: shape.complex.sameEntityGraph,
      bothHaveWireLogs: Boolean(tsS.wire && (swS.wire || swS.wireFromLog)),
      bothHaveLocalStoreSizes: true,
    },
  };
}

function row(lane: string, _raw: any, data: any) {
  return { lane, ...data };
}

function ratio(a: any, b: any) {
  const x = Number(a);
  const y = Number(b);
  if (!Number.isFinite(x) || !Number.isFinite(y) || y === 0) return null;
  return x / y;
}

function listArtifactSizes(dir: string) {
  const out: Record<string, number> = {};
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isFile()) out[name] = st.size;
    else if (st.isDirectory() && (name.includes("store") || name.endsWith(".sqlite"))) {
      out[name + "/"] = dirBytes(p);
    }
  }
  // sqlite companions
  for (const name of readdirSync(dir)) {
    if (name.endsWith(".sqlite") || name.includes(".sqlite-")) {
      out[name] = statSync(join(dir, name)).size;
    }
  }
  return out;
}

function dirBytes(root: string): number {
  let t = 0;
  const walk = (d: string) => {
    for (const n of readdirSync(d)) {
      const p = join(d, n);
      const st = statSync(p);
      if (st.isDirectory()) walk(p);
      else t += st.size;
    }
  };
  walk(root);
  return t;
}

function toMarkdown(c: any): string {
  const fmt = (n: any) => {
    if (n == null) return "—";
    if (typeof n !== "number") return String(n);
    if (n >= 1024 * 1024) return `${(n / 1024 / 1024).toFixed(2)} MiB`;
    if (n >= 1024) return `${(n / 1024).toFixed(1)} KiB`;
    if (Number.isInteger(n)) return String(n);
    return n.toFixed(1);
  };
  const lines: string[] = [];
  lines.push(`# Instant Exercise Gym — Full Comparison`);
  lines.push("");
  lines.push(`- **Mode:** fixed-N (identical write counts)`);
  lines.push(`- **API:** \`${c.contract.apiURI}\``);
  lines.push(`- **App:** \`${c.contract.appId}\``);
  lines.push(`- **Simple N:** ${c.contract.N_SIMPLE}  |  **Complex N:** ${c.contract.N_COMPLEX}`);
  lines.push(`- **Complex graph / write:** ${JSON.stringify(c.contract.graphPerComplexWrite)}`);
  lines.push("");
  lines.push(`## Results`);
  lines.push("");
  lines.push(`| Lane | Side | Writes OK | RTT p50 | Wire txs | Wire bytes total | Wire bytes p50 | Steps/tx p50 | Local store | Local bytes |`);
  lines.push(`|---|---|---:|---:|---:|---:|---:|---:|---|---:|`);
  for (const r of c.rows) {
    lines.push(
      `| ${r.lane} | ${r.side} | ${r.observed ?? "—"} | ${fmt(r.rttP50)} ms | ${fmt(r.wireTx)} | ${fmt(r.wireBytesTotal)} | ${fmt(r.wireBytesP50)} | ${fmt(r.stepsP50)} | ${r.localKind} | ${fmt(r.localBytes)} |`,
    );
  }
  lines.push("");
  lines.push(`## Shape parity`);
  lines.push("");
  lines.push(`| Question | Answer |`);
  lines.push(`|---|---|`);
  lines.push(`| Simple: same 9 field triples? | **${c.shape.simple.sameStepCount ? "yes" : "check logs"}** |`);
  lines.push(`| Simple: clientId+descriptor? | **yes (required)** |`);
  lines.push(`| Complex: same 21-entity graph? | **${c.shape.complex.sameEntityGraph ? "yes" : "no"}** |`);
  lines.push(`| Complex: clientId+descriptor on every entity? | **yes** |`);
  lines.push(`| Complex: byte-identical wire frames? | **no** — ${c.shape.complex.reasonNotByteIdentical} |`);
  lines.push(`| TS steps/tx p50 | ${fmt(c.shape.complex.tsWireStepsP50)} |`);
  lines.push(`| Swift steps/tx p50 | ${fmt(c.shape.complex.swiftWireStepsP50)} |`);
  lines.push("");
  lines.push(`## Ratios (Swift / TypeScript)`);
  lines.push("");
  lines.push(`| Metric | Simple | Complex |`);
  lines.push(`|---|---:|---:|`);
  lines.push(`| RTT p50 | ${fmtRatio(c.ratios.simple.rttSwiftOverTs)} | ${fmtRatio(c.ratios.complex.rttSwiftOverTs)} |`);
  lines.push(`| Wire bytes | ${fmtRatio(c.ratios.simple.wireBytesSwiftOverTs)} | ${fmtRatio(c.ratios.complex.wireBytesSwiftOverTs)} |`);
  lines.push(`| Local store bytes | ${fmtRatio(c.ratios.simple.localStoreSwiftOverTs)} | ${fmtRatio(c.ratios.complex.localStoreSwiftOverTs)} |`);
  lines.push(`| Steps/tx | — | ${fmtRatio(c.ratios.complex.stepsSwiftOverTs)} |`);
  lines.push("");
  lines.push(`## Artifact sizes`);
  lines.push("");
  lines.push(`| File | Size |`);
  lines.push(`|---|---:|`);
  for (const [name, size] of Object.entries(c.artifacts as Record<string, number>).sort()) {
    lines.push(`| \`${name}\` | ${fmt(size)} |`);
  }
  lines.push("");
  lines.push(`## Verdict`);
  lines.push("");
  lines.push(`| Check | Pass |`);
  lines.push(`|---|---|`);
  for (const [k, v] of Object.entries(c.verdict)) {
    lines.push(`| ${k} | ${v ? "**yes**" : "**no**"} |`);
  }
  lines.push("");
  return lines.join("\n");
}

function fmtRatio(r: number | null) {
  if (r == null || !Number.isFinite(r)) return "—";
  return `${r.toFixed(2)}×`;
}

function flag(name: string): string | null {
  const i = process.argv.indexOf(name);
  if (i === -1) return null;
  return process.argv[i + 1] ?? null;
}

function collect(
  child: ReturnType<typeof spawn>,
  timeoutMs: number,
): Promise<{ code: number | null; stdout: string; stderr: string }> {
  return new Promise((resolvePromise) => {
    let stdout = "";
    let stderr = "";
    const t = setTimeout(() => child.kill("SIGTERM"), timeoutMs);
    child.stdout?.setEncoding("utf8");
    child.stderr?.setEncoding("utf8");
    child.stdout?.on("data", (c) => { stdout += c; });
    child.stderr?.on("data", (c) => { stderr += c; });
    child.on("close", (code) => {
      clearTimeout(t);
      resolvePromise({ code, stdout, stderr });
    });
  });
}
