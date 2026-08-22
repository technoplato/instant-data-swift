#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const [swiftPath, typeScriptPath, outputPath = "/tmp/instant-accelerated-transcription-results/comparison.json"] =
  process.argv.slice(2);
if (!swiftPath || !typeScriptPath) {
  throw new Error(
    "Usage: assess-accelerated-transcription-evolution.mjs <swift.json> <typescript.json> [comparison.json]",
  );
}

const swift = JSON.parse(readFileSync(resolve(swiftPath), "utf8"));
const typeScript = JSON.parse(readFileSync(resolve(typeScriptPath), "utf8"));
const failures = [];
const requireEqual = (label, lhs, rhs) => {
  if (lhs !== rhs) failures.push(`${label}: ${lhs} != ${rhs}`);
};
const requireAtLeast = (label, value, minimum) => {
  if (!(value >= minimum)) failures.push(`${label}: ${value} < ${minimum}`);
};
const requireAtMost = (label, value, maximum) => {
  if (!(value <= maximum)) failures.push(`${label}: ${value} > ${maximum}`);
};
const finiteNumber = (label, value) => {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    failures.push(`${label}: missing or non-finite`);
    return 0;
  }
  return value;
};

for (const [name, result] of [["swift", swift], ["typescript", typeScript]]) {
  if (!Array.isArray(result.failures)) failures.push(`${name}: failures array missing`);
  else failures.push(...result.failures.map((failure) => `${name}: ${failure}`));
  requireEqual(`${name} protocol`, result.protocolVersion, 1);
  requireEqual(`${name} logical duration`, result.profile.logicalDurationSeconds, 7_200);
  requireEqual(`${name} segment count`, result.finalSegmentCount, 900);
  requireEqual(`${name} word count`, result.finalWordCount, 18_000);
  requireEqual(`${name} final pending mutations`, result.finalPendingMutationCount, 0);
  requireEqual(`${name} final hash`, result.actualFinalHash, result.expectedFinalHash);
  requireAtLeast(`${name} effective acceleration`, result.effectiveAcceleration, 100);
  requireAtLeast(`${name} revision throughput`, result.revisionThroughputPerSecond, 125);
  requireAtMost(`${name} total wall seconds`, result.totalWallSeconds, 72);
  requireAtMost(`${name} maximum open payload bytes`, result.maximumOpenPayloadBytes, 16 * 1_024);
}
requireEqual("cross-SDK canonical hash", swift.actualFinalHash, typeScript.actualFinalHash);
requireAtMost("Swift peak pending mutations", swift.peakPendingMutationCount, 1_800);

const swiftIncrementalPeak = finiteNumber(
  "Swift incremental peak physical footprint",
  swift.memory.incrementalPeakPhysicalFootprintBytes,
);
const swiftSettledGrowth = finiteNumber(
  "Swift settled physical footprint growth",
  swift.memory.settledPhysicalFootprintGrowthBytes,
);
const typeScriptIncrementalPeak = finiteNumber(
  "TypeScript incremental peak resident memory",
  typeScript.memory.incrementalPeakPhysicalFootprintBytes,
);
const typeScriptSettledGrowth = finiteNumber(
  "TypeScript settled resident memory growth",
  typeScript.memory.settledPhysicalFootprintGrowthBytes,
);
requireAtMost("Swift incremental peak physical footprint", swiftIncrementalPeak, 64 * 1_024 * 1_024);
requireAtMost("Swift settled physical footprint growth", swiftSettledGrowth, 16 * 1_024 * 1_024);
requireAtMost("TypeScript incremental peak resident memory", typeScriptIncrementalPeak, 64 * 1_024 * 1_024);
requireAtMost("TypeScript settled resident memory growth", typeScriptSettledGrowth, 16 * 1_024 * 1_024);
requireAtMost(
  "Swift incremental process memory versus TypeScript",
  Math.max(0, swiftIncrementalPeak),
  Math.max(0, typeScriptIncrementalPeak),
);

const swiftCPUSeconds = finiteNumber(
  "Swift CPU seconds",
  swift.cpu.userSeconds + swift.cpu.systemSeconds,
);
const typeScriptCPUSeconds = finiteNumber(
  "TypeScript CPU seconds",
  typeScript.cpu.userSeconds + typeScript.cpu.systemSeconds,
);
const revisionCount = 9_000;
const swiftCPUPerRevision = swiftCPUSeconds / revisionCount;
const typeScriptCPUPerRevision = typeScriptCPUSeconds / revisionCount;
requireAtMost("Swift CPU seconds per revision versus TypeScript", swiftCPUPerRevision, typeScriptCPUPerRevision);
requireAtMost("Swift wall time versus TypeScript", swift.totalWallSeconds, typeScript.totalWallSeconds);
requireAtMost("Swift average CPU percent", swift.cpu.averagePercentOfOneCore, 200);

const result = {
  protocolVersion: 1,
  case: "accelerated-transcription-evolution.two-hours-100x",
  ok: failures.length === 0,
  policy: {
    logicalDurationSeconds: 7_200,
    minimumAcceleration: 100,
    maximumWallSeconds: 72,
    finalSegmentCount: 900,
    finalWordCount: 18_000,
    revisionCount,
    minimumRevisionThroughputPerSecond: 125,
    maximumOpenPayloadBytes: 16 * 1_024,
    maximumSwiftIncrementalPhysicalFootprintBytes: 64 * 1_024 * 1_024,
    maximumSwiftSettledPhysicalFootprintGrowthBytes: 16 * 1_024 * 1_024,
    maximumSwiftPeakPendingMutations: 1_800,
    swiftMustMeetOrBeatTypeScript: true,
  },
  normalized: {
    swiftCPUSeconds,
    typeScriptCPUSeconds,
    swiftCPUPerRevision,
    typeScriptCPUPerRevision,
    swiftIncrementalPeakBytes: swiftIncrementalPeak,
    typeScriptIncrementalPeakBytes: typeScriptIncrementalPeak,
  },
  failures,
  swift,
  typeScript,
};

const output = resolve(outputPath);
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(result, null, 2)}\n`);
const markdown = [
  "# 100× two-hour transcription evolution",
  "",
  `**Result:** ${result.ok ? "PASS" : "FAIL"}`,
  "",
  `- Swift wall: ${swift.totalWallSeconds.toFixed(3)} s (${swift.effectiveAcceleration.toFixed(2)}×)` ,
  `- TypeScript wall: ${typeScript.totalWallSeconds.toFixed(3)} s (${typeScript.effectiveAcceleration.toFixed(2)}×)`,
  `- Swift throughput: ${swift.revisionThroughputPerSecond.toFixed(2)} revisions/s`,
  `- TypeScript throughput: ${typeScript.revisionThroughputPerSecond.toFixed(2)} revisions/s`,
  `- Swift incremental footprint: ${(swiftIncrementalPeak / 1_048_576).toFixed(2)} MiB`,
  `- TypeScript incremental RSS: ${(typeScriptIncrementalPeak / 1_048_576).toFixed(2)} MiB`,
  `- Swift CPU/revision: ${(swiftCPUPerRevision * 1_000_000).toFixed(2)} µs`,
  `- TypeScript CPU/revision: ${(typeScriptCPUPerRevision * 1_000_000).toFixed(2)} µs`,
  `- Canonical hash: ${swift.actualFinalHash}`,
  "",
  ...(failures.length ? ["## Failures", "", ...failures.map((failure) => `- ${failure}`)] : []),
  "",
].join("\n");
writeFileSync(output.replace(/\.json$/, ".md"), markdown);
process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
if (!result.ok) process.exitCode = 1;
