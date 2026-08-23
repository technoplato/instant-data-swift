#!/usr/bin/env node
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const summaryPath = resolve(process.argv[2] ?? "");
const outputPath = resolve(process.argv[3] ?? "");
if (!process.argv[2] || !process.argv[3]) {
  throw new Error(
    "usage: assert-bidirectional-wire-correctness.mjs SUMMARY.json OUTPUT.json",
  );
}

const summary = JSON.parse(readFileSync(summaryPath, "utf8"));
const scenarios = Array.isArray(summary.scenarios) ? summary.scenarios : [];
const failures = [];

const required = [
  { scenario: "net-a", writerSide: "ts-admin", observerSide: "swift" },
  { scenario: "net-b", writerSide: "swift", observerSide: "ts-admin" },
];

const evidence = [];
for (const requirement of required) {
  const row = scenarios.find((candidate) => candidate.scenario === requirement.scenario);
  if (!row) {
    failures.push(`${requirement.scenario}: missing scenario`);
    continue;
  }

  const writerSequence = Number(row.writer?.maxSeqSeen ?? 0);
  const observerSequence = Number(row.observer?.maxSeqSeen ?? 0);
  const serverSequence = Number(row.serverVerify?.seq ?? 0);
  const writerWordCount = Number(row.writer?.finalWordCount ?? 0);
  const observerWordCount = Number(row.observer?.finalWordCount ?? 0);
  const serverWordCount = Number(row.serverVerify?.wordCount ?? 0);

  const checks = {
    writerSideMatches: row.writerSide === requirement.writerSide,
    observerSideMatches: row.observerSide === requirement.observerSide,
    writerSucceeded: row.writer?.ok === true,
    observerSucceeded: row.observer?.ok === true,
    recordingMaterialized: row.serverVerify?.recordingFound === true,
    segmentMaterialized: row.serverVerify?.segmentFound === true,
    writerProducedUpdates: writerSequence > 0,
    oppositeSDKObservedUpdates: observerSequence > 0,
    oppositeSDKReachedFinalSequence:
      observerSequence === writerSequence && serverSequence === writerSequence,
    oppositeSDKReachedFinalWordCount:
      observerWordCount === writerWordCount && serverWordCount === writerWordCount,
  };

  for (const [name, ok] of Object.entries(checks)) {
    if (!ok) {
      failures.push(
        `${requirement.scenario}.${name}: writerSeq=${writerSequence} observerSeq=${observerSequence} serverSeq=${serverSequence} writerWords=${writerWordCount} observerWords=${observerWordCount} serverWords=${serverWordCount}`,
      );
    }
  }

  evidence.push({
    ...requirement,
    writerSequence,
    observerSequence,
    serverSequence,
    writerWordCount,
    observerWordCount,
    serverWordCount,
    checks,
  });
}

const result = {
  protocol: "instant-bidirectional-wire-correctness-v1",
  ok: failures.length === 0,
  semantics: {
    netA: "TypeScript writer -> Swift live observer -> server ground truth",
    netB: "Swift writer -> TypeScript live observer -> server ground truth",
    openSegmentPolicy:
      "Intermediate complete assignments may be coalesced, but the opposite SDK must observe progress and converge to the exact final sequence and word count.",
  },
  appID: summary.appID ?? null,
  evidence,
  failures,
};

writeFileSync(outputPath, `${JSON.stringify(result, null, 2)}\n`);
process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
assert.equal(result.ok, true, failures.join("\n"));
