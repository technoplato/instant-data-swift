import assert from "node:assert/strict";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const profile = {
  name: "two-hours-100x",
  logicalDurationSeconds: 7_200,
  minimumAcceleration: 100,
  humanWordsPerMinute: 150,
  segmentDurationSeconds: 8,
  wordsPerSegment: 20,
  revisionsPerSegment: 10,
  sampleEveryRevisionCount: 250,
};

const segmentCount = profile.logicalDurationSeconds / profile.segmentDurationSeconds;
const finalWordCount = segmentCount * profile.wordsPerSegment;
const revisionCount = segmentCount * profile.revisionsPerSegment;
const wallBudgetSeconds = profile.logicalDurationSeconds / profile.minimumAcceleration;
const targetRevisionThroughput = revisionCount / wallBudgetSeconds;
const vocabulary = [
  "local", "first", "transcript", "revision", "stays",
  "bounded", "while", "offline", "sync", "converges",
  "without", "losing", "final", "segment", "order",
  "audio", "progress", "remains", "independent", "today",
];

interface TranscriptWord {
  index: number;
  text: string;
  startMilliseconds: number;
  endMilliseconds: number;
  speaker: number;
}

interface TranscriptPayload {
  segmentIndex: number;
  revision: number;
  isFinal: boolean;
  logicalStartMilliseconds: number;
  logicalEndMilliseconds: number;
  words: TranscriptWord[];
}

function segmentID(segmentIndex: number): string {
  return `segment-${String(segmentIndex).padStart(4, "0")}`;
}

function payload(segmentIndex: number, revision: number): TranscriptPayload {
  const wordsPerRevision = profile.wordsPerSegment / profile.revisionsPerSegment;
  const visibleWordCount = Math.min(profile.wordsPerSegment, revision * wordsPerRevision);
  const segmentStart = segmentIndex * profile.segmentDurationSeconds * 1_000;
  const words = Array.from({ length: visibleWordCount }, (_, wordIndex) => {
    const start = segmentStart + wordIndex * 400;
    const base = vocabulary[(segmentIndex + wordIndex) % vocabulary.length];
    return {
      index: wordIndex,
      text: `${base}-${segmentIndex}-${wordIndex}`,
      startMilliseconds: start,
      endMilliseconds: start + 320,
      speaker: segmentIndex % 3,
    };
  });
  return {
    segmentIndex,
    revision,
    isFinal: revision === profile.revisionsPerSegment,
    logicalStartMilliseconds: segmentStart,
    logicalEndMilliseconds: segmentStart + profile.segmentDurationSeconds * 1_000,
    words,
  };
}

function canonicalFinalLine(value: TranscriptPayload): string {
  return [
    segmentID(value.segmentIndex),
    String(value.logicalStartMilliseconds),
    String(value.logicalEndMilliseconds),
    String(value.words.length),
    value.words.map((word) => word.text).join(" "),
  ].join("|");
}

function canonicalHash(lines: Iterable<string>): string {
  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;
  for (const line of lines) {
    for (const byte of Buffer.from(line, "utf8")) {
      hash ^= BigInt(byte);
      hash = BigInt.asUintN(64, hash * prime);
    }
    hash ^= 0x0an;
    hash = BigInt.asUintN(64, hash * prime);
  }
  return hash.toString(16).padStart(16, "0");
}

async function loadCoreInternals() {
  const packageEntry = fileURLToPath(import.meta.resolve("@instantdb/core"));
  const dist = dirname(packageEntry);
  const module = async (path: string) => import(pathToFileURL(resolve(dist, path)).href);
  const [schemaModule, txModule, transformModule, storeModule, queryModule, linkModule, manifest] =
    await Promise.all([
      module("schema.js"),
      module("instatx.js"),
      module("instaml.js"),
      module("store.js"),
      module("instaql.js"),
      module("utils/linkIndex.js"),
      import("@instantdb/core/package.json", { with: { type: "json" } }),
    ]);
  const schema = schemaModule.i.schema({
    entities: {
      segments: schemaModule.i.entity({
        payload: schemaModule.i.string(),
        revision: schemaModule.i.number(),
        isFinal: schemaModule.i.boolean(),
        logicalStartMilliseconds: schemaModule.i.number(),
        logicalEndMilliseconds: schemaModule.i.number(),
      }),
    },
    links: {},
  });
  return {
    schema,
    tx: txModule.tx,
    transform: transformModule.transform,
    transact: storeModule.transact,
    createStore: storeModule.createStore,
    query: queryModule.default,
    makeAttrsStore: () =>
      new storeModule.AttrsStoreClass({}, linkModule.createLinkIndex(schema)),
    version: manifest.default.version as string,
  };
}

function seconds(start: bigint): number {
  return Number(process.hrtime.bigint() - start) / 1_000_000_000;
}

async function main() {
  assert.equal(segmentCount, 900);
  assert.equal(finalWordCount, 18_000);
  assert.equal(revisionCount, 9_000);
  assert.equal(targetRevisionThroughput, 125);

  const core = await loadCoreInternals();
  global.gc?.();
  const baselineRSS = process.memoryUsage().rss;
  let peakRSS = baselineRSS;
  const baselineCPU = process.cpuUsage();
  const started = process.hrtime.bigint();
  const attrsStore = core.makeAttrsStore();
  let context = {
    store: core.createStore(attrsStore, [], true, true),
    attrsStore,
    schema: core.schema,
  };
  const samples: Array<Record<string, number>> = [];
  let completedRevisionCount = 0;
  let maximumOpenPayloadBytes = 0;

  for (let segmentIndex = 0; segmentIndex < segmentCount; segmentIndex += 1) {
    for (let revision = 1; revision <= profile.revisionsPerSegment; revision += 1) {
      const value = payload(segmentIndex, revision);
      const encoded = JSON.stringify(value);
      maximumOpenPayloadBytes = Math.max(
        maximumOpenPayloadBytes,
        Buffer.byteLength(encoded, "utf8"),
      );
      const chunks = [
        core.tx.segments[segmentID(segmentIndex)].update({
          payload: encoded,
          revision,
          isFinal: value.isFinal,
          logicalStartMilliseconds: value.logicalStartMilliseconds,
          logicalEndMilliseconds: value.logicalEndMilliseconds,
        }),
      ];
      const steps = core.transform(context, chunks);
      context = {
        ...core.transact(context.store, context.attrsStore, steps),
        schema: core.schema,
      };
      completedRevisionCount += 1;
      if (
        completedRevisionCount % profile.sampleEveryRevisionCount === 0
        || completedRevisionCount === revisionCount
      ) {
        const rss = process.memoryUsage().rss;
        peakRSS = Math.max(peakRSS, rss);
        samples.push({
          elapsedSeconds: seconds(started),
          logicalSecondsCompleted:
            (completedRevisionCount / revisionCount) * profile.logicalDurationSeconds,
          residentBytes: rss,
          pendingMutationCount: 0,
        });
      }
    }
  }

  const burstWallSeconds = seconds(started);
  const rows = core.query(context, { segments: {} }).data.segments
    .sort((a: { id: string }, b: { id: string }) => a.id.localeCompare(b.id));
  const actualPayloads = rows.map((row: { payload: string }) =>
    JSON.parse(row.payload) as TranscriptPayload
  );
  const actualFinalHash = canonicalHash(actualPayloads.map(canonicalFinalLine));
  const expectedFinalHash = canonicalHash(
    Array.from({ length: segmentCount }, (_, index) =>
      canonicalFinalLine(payload(index, profile.revisionsPerSegment))
    ),
  );
  const actualFinalWordCount = actualPayloads.reduce(
    (total: number, value: TranscriptPayload) => total + value.words.length,
    0,
  );

  global.gc?.();
  const endRSS = process.memoryUsage().rss;
  peakRSS = Math.max(peakRSS, endRSS);
  const totalWallSeconds = seconds(started);
  const cpu = process.cpuUsage(baselineCPU);
  const userSeconds = cpu.user / 1_000_000;
  const systemSeconds = cpu.system / 1_000_000;
  const averagePercentOfOneCore =
    totalWallSeconds > 0 ? ((userSeconds + systemSeconds) / totalWallSeconds) * 100 : 0;
  const effectiveAcceleration = profile.logicalDurationSeconds / totalWallSeconds;
  const revisionThroughputPerSecond = revisionCount / totalWallSeconds;
  const failures: string[] = [];

  if (actualPayloads.length !== segmentCount) {
    failures.push(`final segment count ${actualPayloads.length} != ${segmentCount}`);
  }
  if (
    actualPayloads.some(
      (value) => !value.isFinal || value.revision !== profile.revisionsPerSegment,
    )
  ) {
    failures.push("one or more stored segments is not the final complete assignment");
  }
  if (actualFinalWordCount !== finalWordCount) {
    failures.push(`final word count ${actualFinalWordCount} != ${finalWordCount}`);
  }
  if (actualFinalHash !== expectedFinalHash) {
    failures.push(`final canonical hash ${actualFinalHash} != ${expectedFinalHash}`);
  }
  if (effectiveAcceleration < profile.minimumAcceleration) {
    failures.push(
      `effective acceleration ${effectiveAcceleration.toFixed(2)}x < ${profile.minimumAcceleration}x`,
    );
  }
  if (revisionThroughputPerSecond < targetRevisionThroughput) {
    failures.push(
      `revision throughput ${revisionThroughputPerSecond.toFixed(2)}/s < ${targetRevisionThroughput}/s`,
    );
  }
  if (maximumOpenPayloadBytes > 16 * 1_024) {
    failures.push(`maximum open payload ${maximumOpenPayloadBytes} bytes exceeded 16 KiB`);
  }

  const result = {
    protocolVersion: 1,
    sdk: "typescript",
    coreVersion: core.version,
    profile: {
      ...profile,
      segmentCount,
      finalWordCount,
      revisionCount,
      wallBudgetSeconds,
      targetRevisionThroughput,
    },
    burstWallSeconds,
    settleWallSeconds: 0,
    totalWallSeconds,
    effectiveAcceleration,
    revisionThroughputPerSecond,
    finalSegmentCount: actualPayloads.length,
    finalWordCount: actualFinalWordCount,
    expectedFinalHash,
    actualFinalHash,
    maximumOpenPayloadBytes,
    peakPendingMutationCount: 0,
    finalPendingMutationCount: 0,
    memory: {
      baselinePhysicalFootprintBytes: null,
      peakPhysicalFootprintBytes: null,
      endPhysicalFootprintBytes: null,
      incrementalPeakPhysicalFootprintBytes: peakRSS - baselineRSS,
      settledPhysicalFootprintGrowthBytes: endRSS - baselineRSS,
      peakResidentBytes: peakRSS,
      baselineResidentBytes: baselineRSS,
      endResidentBytes: endRSS,
    },
    cpu: { userSeconds, systemSeconds, averagePercentOfOneCore },
    samples,
    failures,
    ok: failures.length === 0,
  };

  const outputIndex = process.argv.indexOf("--out");
  const output = outputIndex >= 0
    ? resolve(process.argv[outputIndex + 1])
    : resolve("/tmp/instant-accelerated-transcription-results/typescript.json");
  mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, `${JSON.stringify(result, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (!result.ok) process.exitCode = 1;
}

await main();
