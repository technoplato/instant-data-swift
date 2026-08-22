#!/usr/bin/env node

import assert from "node:assert/strict";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const options = parseArgs(process.argv.slice(2));
const mode = options.mode ?? "smoke";
const output = resolve(options.output ?? "validation/results/performance-gate/assessment.json");

const limits = {
  latencyRatio: numberFromEnv("INSTANT_GATE_MAX_LATENCY_RATIO", 1),
  throughputRatio: numberFromEnv("INSTANT_GATE_MIN_THROUGHPUT_RATIO", 1),
  memoryRatio: numberFromEnv("INSTANT_GATE_MAX_MEMORY_RATIO", 1),
  memoryGrowthMiBPerMinute: numberFromEnv(
    "INSTANT_GATE_MAX_MEMORY_GROWTH_MIB_PER_MINUTE",
    0.5,
  ),
  p95Milliseconds: optionalNumberFromEnv("INSTANT_GATE_MAX_P95_MS"),
};

const required = {
  comparison: mode === "smoke" || mode === "full" || mode === "release",
  scribe: mode === "full" || mode === "release",
  exercise: mode === "full" || mode === "release",
};

const inputs = {
  comparison: loadInput("comparison", options.comparison, required.comparison),
  scribe: loadInput("scribe", options.scribe, required.scribe),
  exercise: loadInput("exercise", options.exercise, required.exercise),
};

const failures = [];
const observations = [];

for (const [inputName, document] of Object.entries(inputs)) {
  if (!document) continue;
  inspectDocument(inputName, document);
}

if (inputs.comparison) {
  const comparisons = collectObjects(inputs.comparison).filter((value) =>
    hasFiniteNumber(value.swiftToTypeScriptRatio)
    || hasFiniteNumber(value.actualRatio)
    || hasFiniteNumber(value.ratio)
      && typeof value.name === "string"
  );
  assertOrFail(
    comparisons.length > 0,
    "comparison.no-ratios",
    "The cross-SDK comparison did not contain any comparable Swift/TypeScript metrics.",
  );
  for (const comparison of comparisons) {
    assessComparison(comparison);
  }
}

if (inputs.scribe) {
  const text = JSON.stringify(inputs.scribe).toLowerCase();
  assertOrFail(
    /(neta|admin.?to.?swift|typescript.?to.?swift)/.test(text),
    "scribe.direction-a-missing",
    "The live report does not prove TypeScript writer → Swift reader.",
  );
  assertOrFail(
    /(netb|swift.?to.?admin|swift.?to.?typescript)/.test(text),
    "scribe.direction-b-missing",
    "The live report does not prove Swift writer → TypeScript reader.",
  );
  assertOrFail(
    containsPositiveCount(inputs.scribe, [
      "observed",
      "writesObserved",
      "observedCount",
      "validWrites",
      "seqAdvances",
    ]),
    "scribe.no-observations",
    "The live matrix did not report any observer-visible writes.",
  );
}

if (inputs.exercise) {
  const text = JSON.stringify(inputs.exercise).toLowerCase();
  for (const requiredLane of ["simple", "complex"]) {
    assertOrFail(
      text.includes(requiredLane),
      `exercise.${requiredLane}-missing`,
      `The exercise gym report is missing its ${requiredLane} lane.`,
    );
  }
  assertOrFail(
    text.includes("typescript") && text.includes("swift"),
    "exercise.cross-runtime-missing",
    "The exercise gym must contain both TypeScript and Swift lanes.",
  );
}

const assessment = {
  case: "instant.performance-correctness-gate",
  generatedAt: new Date().toISOString(),
  mode,
  ok: failures.length === 0,
  limits,
  inputFiles: Object.fromEntries(
    Object.entries(options)
      .filter(([key]) => ["comparison", "scribe", "exercise"].includes(key))
      .map(([key, value]) => [key, value ? resolve(value) : null]),
  ),
  summary: {
    observationCount: observations.length,
    failureCount: failures.length,
  },
  failures,
  observations,
};

mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(assessment, null, 2)}\n`);
process.stdout.write(`${JSON.stringify(assessment, null, 2)}\n`);

if (!assessment.ok) {
  process.stderr.write(
    `\nPerformance/correctness gate failed with ${failures.length} violation(s).\n`,
  );
  process.exit(1);
}

function inspectDocument(inputName, document) {
  for (const { path, value } of walk(document)) {
    const key = path.at(-1) ?? "";
    const normalizedKey = key.toLowerCase();

    if (normalizedKey === "ok" && value === false) {
      fail(`${inputName}.${path.join(".")}`, `Reported ok=false at ${path.join(".")}.`);
    }

    if (
      ["lost", "lostcount", "duplicates", "duplicatecount", "reordered", "reorderedcount",
        "finalizationregressions", "postfinalizationregressions", "hashmismatches",
        "correctnessmismatches", "sequenceviolations"].includes(normalizedKey)
      && hasFiniteNumber(value)
      && value !== 0
    ) {
      fail(
        `${inputName}.${path.join(".")}`,
        `${path.join(".")} must be zero but was ${value}.`,
      );
    }

    if (
      ["failures", "errors", "correctnessfailures"].includes(normalizedKey)
      && Array.isArray(value)
      && value.length > 0
    ) {
      fail(
        `${inputName}.${path.join(".")}`,
        `${path.join(".")} contains ${value.length} failure(s).`,
        value,
      );
    }

    if (
      normalizedKey.includes("memory")
      && normalizedKey.includes("slope")
      && hasFiniteNumber(value)
      && value > limits.memoryGrowthMiBPerMinute
    ) {
      fail(
        `${inputName}.${path.join(".")}`,
        `${path.join(".")} grew at ${value} MiB/min; limit is ${limits.memoryGrowthMiBPerMinute} MiB/min.`,
      );
    }

    if (
      limits.p95Milliseconds !== undefined
      && ["p95ms", "p95milliseconds"].includes(normalizedKey)
      && hasFiniteNumber(value)
      && value > limits.p95Milliseconds
    ) {
      fail(
        `${inputName}.${path.join(".")}`,
        `${path.join(".")} was ${value} ms; absolute release limit is ${limits.p95Milliseconds} ms.`,
      );
    }
  }
}

function assessComparison(comparison) {
  const name = comparison.name ?? comparison.case ?? comparison.metric ?? "unnamed";
  const ratio = firstFinite(
    comparison.swiftToTypeScriptRatio,
    comparison.actualRatio,
    comparison.ratio,
  );
  if (ratio === undefined) return;

  const haystack = `${name} ${comparison.unit ?? ""} ${comparison.category ?? ""}`.toLowerCase();
  const isThroughput = /(throughput|writes.?per.?second|observed.?per.?second|ops.?per.?second)/.test(haystack);
  const isMemory = /(memory|rss|resident|footprint|heap|allocated|bytes)/.test(haystack);
  const limit = isThroughput
    ? limits.throughputRatio
    : isMemory
      ? limits.memoryRatio
      : limits.latencyRatio;
  const passes = isThroughput ? ratio >= limit : ratio <= limit;

  observations.push({
    name,
    kind: isThroughput ? "throughput" : isMemory ? "memory" : "latency-or-cost",
    swiftToTypeScriptRatio: ratio,
    required: isThroughput ? `>= ${limit}` : `<= ${limit}`,
    passes,
  });

  if (!passes) {
    fail(
      `comparison.${name}`,
      `${name}: Swift/TypeScript ratio ${ratio.toFixed(4)} must be ${isThroughput ? ">=" : "<="} ${limit}.`,
      comparison,
    );
  }

  if (comparison.status === "optimization-target") {
    fail(
      `comparison.${name}.optimization-target`,
      `${name} remains an optimization target and cannot pass a release gate.`,
      comparison.optimizationTarget,
    );
  }
}

function loadInput(name, path, isRequired) {
  if (!path) {
    if (isRequired) fail(`input.${name}.missing`, `Missing --${name} report for mode=${mode}.`);
    return null;
  }
  const absolute = resolve(path);
  if (!existsSync(absolute)) {
    if (isRequired) fail(`input.${name}.not-found`, `Required report does not exist: ${absolute}`);
    return null;
  }
  try {
    return JSON.parse(readFileSync(absolute, "utf8"));
  } catch (error) {
    fail(`input.${name}.invalid-json`, `Could not parse ${absolute}: ${error.message}`);
    return null;
  }
}

function* walk(value, path = []) {
  yield { path, value };
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) {
      yield* walk(value[index], [...path, String(index)]);
    }
  } else if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      yield* walk(child, [...path, key]);
    }
  }
}

function collectObjects(value) {
  return [...walk(value)].map(({ value: candidate }) => candidate).filter(
    (candidate) => candidate && typeof candidate === "object" && !Array.isArray(candidate),
  );
}

function containsPositiveCount(document, names) {
  const allowed = new Set(names.map((name) => name.toLowerCase()));
  return [...walk(document)].some(({ path, value }) =>
    allowed.has((path.at(-1) ?? "").toLowerCase())
    && hasFiniteNumber(value)
    && value > 0
  );
}

function parseArgs(args) {
  const result = {};
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    assert.ok(argument.startsWith("--"), `Unexpected argument: ${argument}`);
    const key = argument.slice(2);
    const value = args[index + 1];
    assert.ok(value && !value.startsWith("--"), `Missing value for ${argument}`);
    result[key] = value;
    index += 1;
  }
  return result;
}

function assertOrFail(condition, id, message, details) {
  if (!condition) fail(id, message, details);
}

function fail(id, message, details) {
  failures.push({ id, message, ...(details === undefined ? {} : { details }) });
}

function hasFiniteNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

function firstFinite(...values) {
  return values.find(hasFiniteNumber);
}

function numberFromEnv(name, fallback) {
  const value = process.env[name];
  if (value === undefined || value === "") return fallback;
  const parsed = Number(value);
  assert.ok(Number.isFinite(parsed), `${name} must be a finite number.`);
  return parsed;
}

function optionalNumberFromEnv(name) {
  const value = process.env[name];
  if (value === undefined || value === "") return undefined;
  const parsed = Number(value);
  assert.ok(Number.isFinite(parsed), `${name} must be a finite number.`);
  return parsed;
}
