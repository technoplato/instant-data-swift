#!/usr/bin/env node

import assert from "node:assert/strict";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const args = parseArgs(process.argv.slice(2));
const mode = args.mode ?? "smoke";
assert.ok(["smoke", "full", "release"].includes(mode), `Unsupported mode: ${mode}`);

const failures = [];
const observations = [];
const limits = {
  baselineTolerance: envNumber("INSTANT_GATE_BASELINE_TOLERANCE", 0.03),
  newWorkloadCostRatio: envNumber("INSTANT_GATE_NEW_WORKLOAD_MAX_COST_RATIO", 1.25),
  maxCostRatio: envNumber("INSTANT_GATE_MAX_COST_RATIO", 1),
  minThroughputRatio: envNumber("INSTANT_GATE_MIN_THROUGHPUT_RATIO", 1),
  maxMemoryRatio: envNumber("INSTANT_GATE_MAX_MEMORY_RATIO", 1),
  maxMemoryGrowthMiBPerMinute: envNumber(
    "INSTANT_GATE_MAX_MEMORY_GROWTH_MIB_PER_MINUTE",
    0.5,
  ),
};

const comparison = load("comparison", args.comparison, true);
const baseline = load("baseline", args.baseline, mode === "smoke");
const scribe = load("scribe", args.scribe, mode !== "smoke");
const exercise = load("exercise", args.exercise, mode !== "smoke");

for (const [name, document] of Object.entries({ comparison, scribe, exercise })) {
  if (document) assessCorrectness(name, document);
}

const currentRows = comparison ? comparisonRows(comparison) : [];
const baselineRows = baseline ? new Map(comparisonRows(baseline).map((row) => [row.name, row])) : new Map();

if (currentRows.length === 0) {
  fail("comparison.empty", "No Swift/TypeScript comparison rows were found.");
}

for (const row of currentRows) {
  const historical = baselineRows.get(row.name);
  const releaseStrict = mode !== "smoke";
  const required = releaseStrict
    ? strictRequirement(row.kind)
    : regressionRequirement(row, historical);
  const passes = row.kind === "throughput"
    ? row.ratio >= required.limit
    : row.ratio <= required.limit;

  observations.push({
    name: row.name,
    kind: row.kind,
    ratio: row.ratio,
    sourceStatus: row.status,
    required: `${row.kind === "throughput" ? ">=" : "<="} ${required.limit}`,
    policy: required.policy,
    passes,
  });

  if (!passes) {
    fail(
      `performance.${row.name}`,
      `${row.name}: Swift/TypeScript ${row.kind} ratio ${row.ratio.toFixed(4)} must be ${row.kind === "throughput" ? ">=" : "<="} ${required.limit.toFixed(4)} (${required.policy}).`,
      { current: row.raw, baseline: historical?.raw ?? null },
    );
  }

  if (releaseStrict && row.status === "optimization-target") {
    fail(
      `performance.${row.name}.optimization-target`,
      `${row.name} is still classified as an optimization target; release mode requires parity or better.`,
      row.raw.optimizationTarget,
    );
  }
}

if (mode !== "smoke") {
  requireBidirectionalLive(scribe);
  requireExerciseCoverage(exercise);
}

const result = {
  case: "instant.performance-correctness-gate",
  generatedAt: new Date().toISOString(),
  mode,
  ok: failures.length === 0,
  limits,
  summary: {
    comparisonCount: currentRows.length,
    observationCount: observations.length,
    failureCount: failures.length,
  },
  observations,
  failures,
};

const output = resolve(args.output ?? "validation/results/performance-gate/assessment.json");
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(result, null, 2)}\n`);
process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
if (!result.ok) process.exit(1);

function strictRequirement(kind) {
  if (kind === "throughput") return { limit: limits.minThroughputRatio, policy: "release throughput parity" };
  if (kind === "memory") return { limit: limits.maxMemoryRatio, policy: "release memory parity" };
  return { limit: limits.maxCostRatio, policy: "release latency/cost parity" };
}

function regressionRequirement(row, historical) {
  if (!historical) {
    if (row.kind === "throughput") {
      return {
        limit: 1 / limits.newWorkloadCostRatio,
        policy: "new-workload bootstrap floor",
      };
    }
    return {
      limit: limits.newWorkloadCostRatio,
      policy: "new-workload bootstrap ceiling",
    };
  }
  if (row.kind === "throughput") {
    return {
      limit: historical.ratio * (1 - limits.baselineTolerance),
      policy: "checked-in baseline regression floor",
    };
  }
  return {
    limit: historical.ratio * (1 + limits.baselineTolerance),
    policy: "checked-in baseline regression ceiling",
  };
}

function assessCorrectness(source, document) {
  for (const { path, value } of walk(document)) {
    const key = (path.at(-1) ?? "").toLowerCase();
    if (key === "ok" && value === false) {
      fail(`${source}.${path.join(".")}`, `Reported ok=false at ${path.join(".")}.`);
    }
    if (
      /^(lost|lostcount|duplicates|duplicatecount|reordered|reorderedcount|hashmismatches|correctnessmismatches|sequenceviolations|postfinalizationregressions|finalizationregressions)$/.test(key)
      && finite(value)
      && value !== 0
    ) {
      fail(`${source}.${path.join(".")}`, `${path.join(".")} must be zero, not ${value}.`);
    }
    if (/^(failures|errors|correctnessfailures)$/.test(key) && Array.isArray(value) && value.length > 0) {
      fail(`${source}.${path.join(".")}`, `${path.join(".")} contains ${value.length} failure(s).`, value);
    }
    if (
      /memory.*slope|slope.*memory|rss.*slope|slope.*rss/.test(key)
      && finite(value)
      && value > limits.maxMemoryGrowthMiBPerMinute
    ) {
      fail(
        `${source}.${path.join(".")}`,
        `${path.join(".")} is ${value} MiB/min; maximum is ${limits.maxMemoryGrowthMiBPerMinute}.`,
      );
    }
  }
}

function comparisonRows(document) {
  const byName = new Map();
  for (const candidate of objects(document)) {
    const name = typeof candidate.name === "string" ? candidate.name : null;
    const ratio = firstFinite(
      candidate.swiftToTypeScriptRatio,
      candidate.actualRatio,
      candidate.ratio,
    );
    if (!name || ratio === undefined) continue;
    const kind = classify(name, candidate);
    byName.set(name, {
      name,
      ratio,
      kind,
      status: candidate.status,
      raw: candidate,
    });
  }
  return [...byName.values()];
}

function classify(name, candidate) {
  const text = `${name} ${candidate.unit ?? ""} ${candidate.category ?? ""}`.toLowerCase();
  if (/throughput|writes.?per.?second|observed.?per.?second|ops.?per.?second/.test(text)) return "throughput";
  if (/memory|rss|resident|footprint|heap|allocated|bytes/.test(text)) return "memory";
  return "cost";
}

function requireBidirectionalLive(document) {
  if (!document) return;
  const text = JSON.stringify(document).toLowerCase();
  assertion(
    /(neta|admin.?to.?swift|typescript.?to.?swift)/.test(text),
    "live.typescript-to-swift-missing",
    "Live evidence must contain TypeScript writer → Swift reader.",
  );
  assertion(
    /(netb|swift.?to.?admin|swift.?to.?typescript)/.test(text),
    "live.swift-to-typescript-missing",
    "Live evidence must contain Swift writer → TypeScript reader.",
  );
  assertion(
    positiveNamedCount(document, /observed|validwrites|seqadvances|writesobserved/),
    "live.no-observed-writes",
    "Live evidence did not contain a positive observer-visible write count.",
  );
}

function requireExerciseCoverage(document) {
  if (!document) return;
  const text = JSON.stringify(document).toLowerCase();
  for (const token of ["swift", "typescript", "simple", "complex", "stream", "linked"]) {
    assertion(text.includes(token), `exercise.${token}-missing`, `Exercise report is missing ${token} coverage.`);
  }
}

function positiveNamedCount(document, pattern) {
  return [...walk(document)].some(({ path, value }) =>
    pattern.test((path.at(-1) ?? "").toLowerCase()) && finite(value) && value > 0
  );
}

function load(name, path, required) {
  if (!path) {
    if (required) fail(`input.${name}.missing`, `Missing --${name}.`);
    return null;
  }
  const absolute = resolve(path);
  if (!existsSync(absolute)) {
    if (required) fail(`input.${name}.not-found`, `Missing report: ${absolute}`);
    return null;
  }
  try {
    return JSON.parse(readFileSync(absolute, "utf8"));
  } catch (error) {
    fail(`input.${name}.invalid-json`, `Could not parse ${absolute}: ${error.message}`);
    return null;
  }
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 2) {
    const key = values[index];
    const value = values[index + 1];
    assert.ok(key?.startsWith("--") && value, `Invalid arguments near ${key ?? "end"}.`);
    parsed[key.slice(2)] = value;
  }
  return parsed;
}

function* walk(value, path = []) {
  yield { path, value };
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) yield* walk(value[index], [...path, String(index)]);
  } else if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) yield* walk(child, [...path, key]);
  }
}

function objects(value) {
  return [...walk(value)].map(({ value: candidate }) => candidate).filter(
    (candidate) => candidate && typeof candidate === "object" && !Array.isArray(candidate),
  );
}

function firstFinite(...values) {
  return values.find(finite);
}

function finite(value) {
  return typeof value === "number" && Number.isFinite(value);
}

function envNumber(name, fallback) {
  const value = process.env[name];
  if (value === undefined || value === "") return fallback;
  const parsed = Number(value);
  assert.ok(Number.isFinite(parsed), `${name} must be finite.`);
  return parsed;
}

function assertion(condition, id, message, details) {
  if (!condition) fail(id, message, details);
}

function fail(id, message, details) {
  failures.push({ id, message, ...(details === undefined ? {} : { details }) });
}
