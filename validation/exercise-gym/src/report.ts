import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const args = parseArgs(process.argv.slice(2));
const comparisonPath = resolve(required("comparison"));
const scribePath = resolve(required("scribe"));
const outputPath = resolve(required("out"));
const comparison = JSON.parse(readFileSync(comparisonPath, "utf8"));
const scribe = JSON.parse(readFileSync(scribePath, "utf8"));

const rows = extractRows(comparison);
const simple = rows.filter((row) => /transaction|triple|enqueue|restore|reconnect/i.test(row.name));
const complex = rows.filter((row) => !simple.includes(row));
const correctnessFailures = collectCorrectnessFailures({ comparison, scribe });
const optimizationTargets = rows.filter((row) => row.status === "optimization-target");

const report = {
  case: "instant.exercise-gym.consolidated",
  generatedAt: new Date().toISOString(),
  ok: correctnessFailures.length === 0 && optimizationTargets.length === 0,
  sources: {
    deterministicCrossSDK: comparisonPath,
    bidirectionalScribeLive: scribePath,
  },
  coverage: [
    "simple transaction and triple workloads",
    "complex flat nested reverse and linked queries",
    "stream write and stream read for progressive audio",
    "durable offline enqueue restore and reconnect drain",
    "rapid open segment rewriting and finalization",
    "TypeScript writer to Swift reader",
    "Swift writer to TypeScript reader",
  ],
  suites: {
    "swift:simple": side(simple, "swift"),
    "typescript:simple": side(simple, "typescript"),
    "swift:complex": side(complex, "swift"),
    "typescript:complex": side(complex, "typescript"),
  },
  compare: {
    simple: summary(simple),
    complex: summary(complex),
  },
  correctnessFailures,
  optimizationTargets,
  comparisons: rows,
};

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`);
writeFileSync(outputPath.replace(/\.json$/, ".md"), markdown(report));
process.stdout.write(`${JSON.stringify({
  event: "consolidated-exercise-gym-report",
  ok: report.ok,
  comparisonCount: rows.length,
  correctnessFailureCount: correctnessFailures.length,
  optimizationTargetCount: optimizationTargets.length,
  outputPath,
}, null, 2)}\n`);

function required(name) {
  if (!args[name]) throw new Error(`Missing --${name}`);
  return args[name];
}

function extractRows(document) {
  const rows = new Map();
  for (const candidate of objects(document)) {
    if (typeof candidate.name !== "string") continue;
    const ratio = firstFinite(candidate.swiftToTypeScriptRatio, candidate.actualRatio, candidate.ratio);
    if (ratio === undefined) continue;
    const text = `${candidate.name} ${candidate.unit ?? ""}`.toLowerCase();
    const kind = /throughput|per.?second/.test(text)
      ? "throughput"
      : /memory|rss|resident|footprint|heap|bytes/.test(text)
        ? "memory"
        : "cost";
    const swift = firstFinite(
      candidate.swiftP50Nanoseconds,
      candidate.swiftNanosecondsPerUnit,
      candidate.swift,
      ratio,
    );
    const typescript = firstFinite(
      candidate.typeScriptP50Nanoseconds,
      candidate.typeScriptNanosecondsPerUnit,
      candidate.typescript,
      1,
    );
    const passes = kind === "throughput" ? ratio >= 1 : ratio <= 1;
    rows.set(candidate.name, {
      name: candidate.name,
      kind,
      swift,
      typescript,
      swiftToTypeScriptRatio: ratio,
      status: passes ? "meets-or-exceeds" : "optimization-target",
      sourceStatus: candidate.status ?? null,
    });
  }
  return [...rows.values()];
}

function collectCorrectnessFailures(document) {
  const failures = [];
  for (const { path, value } of walk(document)) {
    const key = (path.at(-1) ?? "").toLowerCase();
    if (key === "ok" && value === false) failures.push({ path: path.join("."), value });
    if (
      /^(lost|lostcount|duplicates|duplicatecount|reordered|reorderedcount|hashmismatches|sequenceviolations|postfinalizationregressions)$/.test(key)
      && typeof value === "number"
      && value !== 0
    ) {
      failures.push({ path: path.join("."), value });
    }
    if (/^(failures|errors)$/.test(key) && Array.isArray(value) && value.length > 0) {
      failures.push({ path: path.join("."), value });
    }
  }
  return failures;
}

function side(rows, name) {
  return {
    side: name,
    metricCount: rows.length,
    metrics: rows.map((row) => ({
      name: row.name,
      kind: row.kind,
      value: name === "swift" ? row.swift : row.typescript,
    })),
  };
}

function summary(rows) {
  return {
    metricCount: rows.length,
    passCount: rows.filter((row) => row.status === "meets-or-exceeds").length,
    failCount: rows.filter((row) => row.status === "optimization-target").length,
    rows,
  };
}

function markdown(report) {
  const lines = [
    "# Consolidated cross-runtime exercise gym",
    "",
    `- Result: **${report.ok ? "PASS" : "FAIL"}**`,
    `- Comparisons: ${report.comparisons.length}`,
    `- Correctness failures: ${report.correctnessFailures.length}`,
    `- Optimization targets: ${report.optimizationTargets.length}`,
    "",
    "| Workload | Kind | Swift | TypeScript | Swift / TS | Status |",
    "|---|---|---:|---:|---:|---|",
  ];
  for (const row of report.comparisons) {
    lines.push(
      `| ${row.name} | ${row.kind} | ${format(row.swift)} | ${format(row.typescript)} | ${row.swiftToTypeScriptRatio.toFixed(3)} | ${row.status} |`,
    );
  }
  return `${lines.join("\n")}\n`;
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 2) {
    const key = values[index];
    const value = values[index + 1];
    if (!key?.startsWith("--") || !value) throw new Error(`Invalid arguments near ${key ?? "end"}`);
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
  return values.find((value) => typeof value === "number" && Number.isFinite(value));
}

function format(value) {
  return Math.abs(value) > 1_000_000 ? value.toExponential(3) : value.toFixed(3);
}
