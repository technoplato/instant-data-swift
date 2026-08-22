import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import os from "node:os";
import { resolve } from "node:path";

interface JsonObject {
  [key: string]: unknown;
}

interface ComparisonRow {
  name: string;
  kind: "latency-or-cost" | "throughput" | "memory";
  swift: number;
  typescript: number;
  swiftToTypeScriptRatio: number;
  status: "meets-or-exceeds" | "optimization-target";
  source: string;
}

const args = parseArgs(process.argv.slice(2));
const suite = args.suite ?? "all";
const outDir = resolve(args.out ?? "artifacts/consolidated");
mkdirSync(outDir, { recursive: true });

const crossPath = resolve(
  process.env.INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_RESULTS_DIR
    ? `${process.env.INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_RESULTS_DIR}/comparison.json`
    : "../cross-sdk/comparison.json",
);
const scribePath = resolve(
  process.env.INSTANT_SWIFT_DATA_BENCH_RESULTS_DIR
    ? `${process.env.INSTANT_SWIFT_DATA_BENCH_RESULTS_DIR}/summary.json`
    : "../scribe-live/summary.json",
);

const cross = readRequiredJSON(crossPath);
const scribe = readRequiredJSON(scribePath);
const rows = [...rowsFromCrossSDK(cross), ...rowsFromLiveMatrix(scribe)];

const correctnessFailures = collectCorrectnessFailures({ cross, scribe });
const optimizationTargets = rows.filter((row) => row.status === "optimization-target");
const simpleRows = rows.filter((row) => isSimple(row.name));
const complexRows = rows.filter((row) => !isSimple(row.name));

const report = {
  case: "instant.exercise-gym.consolidated",
  generatedAt: new Date().toISOString(),
  suite,
  ok: correctnessFailures.length === 0 && optimizationTargets.length === 0,
  environment: {
    platform: os.platform(),
    release: os.release(),
    architecture: os.arch(),
    node: process.version,
    cpuModel: os.cpus()[0]?.model ?? "unknown",
    cpuCount: os.cpus().length,
    totalMemoryBytes: os.totalmem(),
    resourceUsage: process.resourceUsage(),
    processMemory: process.memoryUsage(),
  },
  inputEvidence: {
    crossSDKComparison: crossPath,
    scribeBidirectionalLive: scribePath,
  },
  coverage: [
    "transaction lowering",
    "triple insert update and retract",
    "flat nested and reverse linked queries",
    "high-frequency linked writes",
    "durable enqueue relaunch restore and reconnect drain",
    "storage metadata query",
    "progressive stream write and read",
    "rapid open-segment rewrite and finalization",
    "TypeScript writer to Swift reader",
    "Swift writer to TypeScript reader",
  ],
  suites: {
    "typescript:simple": sideSummary(simpleRows, "typescript"),
    "swift:simple": sideSummary(simpleRows, "swift"),
    "typescript:complex": sideSummary(complexRows, "typescript"),
    "swift:complex": sideSummary(complexRows, "swift"),
  },
  compare: {
    simple: summarizeRows(simpleRows),
    complex: summarizeRows(complexRows),
  },
  correctnessFailures,
  optimizationTargets,
  comparisons: rows,
};

writeFileSync(`${outDir}/report.json`, `${JSON.stringify(report, null, 2)}\n`);
writeFileSync(`${outDir}/report.md`, markdown(report));
process.stdout.write(`${JSON.stringify({
  event: "exercise-gym-complete",
  ok: report.ok,
  outDir,
  comparisons: rows.length,
  optimizationTargets: optimizationTargets.length,
  correctnessFailures: correctnessFailures.length,
}, null, 2)}\n`);

if (!report.ok) process.exitCode = 1;

function rowsFromCrossSDK(document: JsonObject): ComparisonRow[] {
  const rows: ComparisonRow[] = [];
  for (const candidate of collectObjects(document)) {
    const name = string(candidate.name);
    const ratio = number(candidate.swiftToTypeScriptRatio) ?? number(candidate.actualRatio);
    if (!name || ratio === undefined) continue;
    const swift =
      number(candidate.swiftP50Nanoseconds)
      ?? number(candidate.swiftNanosecondsPerUnit)
      ?? ratio;
    const typescript =
      number(candidate.typeScriptP50Nanoseconds)
      ?? number(candidate.typeScriptNanosecondsPerUnit)
      ?? 1;
    const kind = classify(name);
    rows.push({
      name,
      kind,
      swift,
      typescript,
      swiftToTypeScriptRatio: ratio,
      status: passes(kind, ratio) ? "meets-or-exceeds" : "optimization-target",
      source: "cross-sdk deterministic release benchmark",
    });
  }
  return deduplicate(rows);
}

function rowsFromLiveMatrix(document: JsonObject): ComparisonRow[] {
  const rows: ComparisonRow[] = [];
  const samples = numericPaths(document);

  addPairedMetric(
    rows,
    samples,
    "live.observed-throughput",
    /(?:observed|valid).*per.*second|observedpersecond|validwritespersecond/i,
    "throughput",
  );
  addPairedMetric(
    rows,
    samples,
    "live.p50-latency",
    /(?:latency|rtt).*p50|p50.*(?:latency|rtt)|p50ms/i,
    "latency-or-cost",
  );
  addPairedMetric(
    rows,
    samples,
    "live.incremental-peak-rss",
    /(?:incremental|attributed|app).*rss|peakapp.*rss|incremental.*memory/i,
    "memory",
  );
  addPairedMetric(
    rows,
    samples,
    "live.settled-rss",
    /settled.*rss|steady.*rss|settled.*memory/i,
    "memory",
  );

  return rows;
}

function addPairedMetric(
  rows: ComparisonRow[],
  samples: Array<{ path: string; value: number }>,
  name: string,
  metric: RegExp,
  kind: ComparisonRow["kind"],
): void {
  const swift = maximum(
    samples.filter(({ path }) => /swift/i.test(path) && metric.test(path)).map(({ value }) => value),
  );
  const typescript = maximum(
    samples
      .filter(({ path }) => /typescript|admin|\bts\b/i.test(path) && metric.test(path))
      .map(({ value }) => value),
  );
  if (swift === undefined || typescript === undefined || typescript === 0) return;
  const ratio = swift / typescript;
  rows.push({
    name,
    kind,
    swift,
    typescript,
    swiftToTypeScriptRatio: ratio,
    status: passes(kind, ratio) ? "meets-or-exceeds" : "optimization-target",
    source: "Scribe-shaped bidirectional live matrix",
  });
}

function collectCorrectnessFailures(input: JsonObject): Array<{ path: string; value: unknown }> {
  const failures: Array<{ path: string; value: unknown }> = [];
  for (const { path, value } of walk(input)) {
    const key = path.at(-1)?.toLowerCase() ?? "";
    if (key === "ok" && value === false) failures.push({ path: path.join("."), value });
    if (
      /^(lost|lostcount|duplicates|duplicatecount|reordered|reorderedcount|hashmismatches|sequenceviolations|postfinalizationregressions)$/.test(key)
      && typeof value === "number"
      && value !== 0
    ) {
      failures.push({ path: path.join("."), value });
    }
    if (/failures|errors/.test(key) && Array.isArray(value) && value.length > 0) {
      failures.push({ path: path.join("."), value });
    }
  }
  return failures;
}

function sideSummary(rows: ComparisonRow[], side: "swift" | "typescript") {
  return {
    side,
    metricCount: rows.length,
    metrics: rows.map((row) => ({
      name: row.name,
      kind: row.kind,
      value: side === "swift" ? row.swift : row.typescript,
      source: row.source,
    })),
  };
}

function summarizeRows(rows: ComparisonRow[]) {
  return {
    metricCount: rows.length,
    passCount: rows.filter((row) => row.status === "meets-or-exceeds").length,
    failCount: rows.filter((row) => row.status === "optimization-target").length,
    rows,
  };
}

function markdown(report: typeof report): string {
  const lines = [
    "# Consolidated Instant exercise gym",
    "",
    `- Result: **${report.ok ? "PASS" : "FAIL"}**`,
    `- Comparisons: ${report.comparisons.length}`,
    `- Optimization targets: ${report.optimizationTargets.length}`,
    `- Correctness failures: ${report.correctnessFailures.length}`,
    "",
    "| Workload | Kind | Swift | TypeScript | Swift / TS | Status |",
    "|---|---:|---:|---:|---:|---|",
  ];
  for (const row of report.comparisons) {
    lines.push(
      `| ${row.name} | ${row.kind} | ${format(row.swift)} | ${format(row.typescript)} | ${row.swiftToTypeScriptRatio.toFixed(3)} | ${row.status} |`,
    );
  }
  lines.push("");
  return `${lines.join("\n")}\n`;
}

function classify(name: string): ComparisonRow["kind"] {
  if (/throughput|per.?second|ops.?\/s|writes.?\/s/i.test(name)) return "throughput";
  if (/memory|rss|resident|footprint|heap|allocated|bytes/i.test(name)) return "memory";
  return "latency-or-cost";
}

function passes(kind: ComparisonRow["kind"], ratio: number): boolean {
  return kind === "throughput" ? ratio >= 1 : ratio <= 1;
}

function isSimple(name: string): boolean {
  return /transaction-transform|triple-(?:insert|update|retract)|pending-mutation-enqueue|offline-restore|reconnect-outbox-drain|live\.observed|live\.p50/i.test(name);
}

function readRequiredJSON(path: string): JsonObject {
  if (!existsSync(path)) throw new Error(`Missing required evidence: ${path}`);
  return JSON.parse(readFileSync(path, "utf8")) as JsonObject;
}

function parseArgs(input: string[]): Record<string, string> {
  const result: Record<string, string> = {};
  for (let index = 0; index < input.length; index += 2) {
    const key = input[index];
    const value = input[index + 1];
    if (!key?.startsWith("--") || !value) throw new Error(`Invalid arguments near ${key ?? "end"}`);
    result[key.slice(2)] = value;
  }
  return result;
}

function* walk(value: unknown, path: string[] = []): Generator<{ path: string[]; value: unknown }> {
  yield { path, value };
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) yield* walk(value[index], [...path, String(index)]);
  } else if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) yield* walk(child, [...path, key]);
  }
}

function collectObjects(value: unknown): JsonObject[] {
  return [...walk(value)]
    .map(({ value: candidate }) => candidate)
    .filter((candidate): candidate is JsonObject => Boolean(candidate) && typeof candidate === "object" && !Array.isArray(candidate));
}

function numericPaths(value: unknown): Array<{ path: string; value: number }> {
  return [...walk(value)]
    .filter((entry): entry is { path: string[]; value: number } => typeof entry.value === "number" && Number.isFinite(entry.value))
    .map(({ path, value }) => ({ path: path.join("."), value }));
}

function number(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function string(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function maximum(values: number[]): number | undefined {
  return values.length ? Math.max(...values) : undefined;
}

function deduplicate(rows: ComparisonRow[]): ComparisonRow[] {
  const byName = new Map<string, ComparisonRow>();
  for (const row of rows) byName.set(row.name, row);
  return [...byName.values()];
}

function format(value: number): string {
  if (Math.abs(value) >= 1_000_000) return value.toExponential(3);
  return value.toFixed(3);
}
