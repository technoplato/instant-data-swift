import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  AttrsStoreClass,
  createStore,
} from "../../upstream/instant/client/packages/core/src/store.ts";

type InstantAttr = {
  id: string;
  "value-type": "blob" | "ref";
  cardinality: "one" | "many";
  "forward-identity": [string, string, string];
  "reverse-identity"?: [string, string, string];
  "unique?": boolean;
  "index?": boolean;
  "checked-data-type"?: "string" | "number" | "boolean" | "date";
  "on-delete"?: string;
  "on-delete-reverse"?: string;
};

export type Triple = [string, string, unknown, number];

export type BenchmarkOptions = {
  iterations: number;
  warmups: number;
  jsonl: boolean;
};

export type BenchmarkSample = {
  iteration: number;
  durationNanoseconds: number;
  operationCount?: number;
  resultCount?: number;
  memoryBeforeBytes: number;
  memoryAfterBytes: number;
  memoryDeltaBytes: number;
};

export type BenchmarkMetric = {
  name: string;
  description: string;
  fixture: string;
  fixtureHash: string;
  source: string;
  unit: "nanoseconds";
  operationCount?: number;
  resultCount?: number;
  correctnessHash: string;
  samples: BenchmarkSample[];
  minNanoseconds: number;
  p50Nanoseconds: number;
  p95Nanoseconds: number;
  maxNanoseconds: number;
  averageNanoseconds: number;
};

export type BenchmarkRun = {
  suite: string;
  side: "typescript";
  upstreamRevision: string;
  nodeVersion: string;
  platform: string;
  arch: string;
  iterations: number;
  warmups: number;
  timestampMs: number;
  metrics: BenchmarkMetric[];
};

export type BenchmarkCaseResult = {
  operationCount?: number;
  resultCount?: number;
  correctness: unknown;
};

export type BenchmarkCase<Prepared = unknown> = {
  name: string;
  description: string;
  fixture: string;
  fixtureHash: string;
  source: string;
  prepare?: () => Prepared;
  run: (prepared: Prepared) => BenchmarkCaseResult;
};

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = resolve(scriptDirectory, "../..");
export const upstreamInstantRoot = resolve(repositoryRoot, "upstream/instant");
export const upstreamClientRoot = resolve(upstreamInstantRoot, "client");
export const upstreamCoreRoot = resolve(upstreamClientRoot, "packages/core");

export const sourceLabels = {
  instaql: "upstream/instant/client/packages/core/src/instaql.ts",
  store: "upstream/instant/client/packages/core/src/store.ts",
  instaml: "upstream/instant/client/packages/core/src/instaml.ts",
  instatx: "upstream/instant/client/packages/core/src/instatx.ts",
  infiniteQuery: "upstream/instant/client/packages/core/src/infiniteQuery.ts",
};

export function parseBenchmarkOptions(
  argv: string[],
  defaults: BenchmarkOptions = { iterations: 20, warmups: 5, jsonl: false },
): BenchmarkOptions {
  const options = { ...defaults };
  const args = [...argv];

  while (args.length > 0) {
    const arg = args.shift();
    switch (arg) {
      case "--iterations":
      case "-n": {
        const value = Number(args.shift());
        if (!Number.isInteger(value) || value <= 0) {
          throw new Error("Expected --iterations to be a positive integer.");
        }
        options.iterations = value;
        break;
      }

      case "--warmups": {
        const value = Number(args.shift());
        if (!Number.isInteger(value) || value < 0) {
          throw new Error("Expected --warmups to be a non-negative integer.");
        }
        options.warmups = value;
        break;
      }

      case "--jsonl":
        options.jsonl = true;
        break;

      case "--help":
      case "-h":
        throw new Error(
          "Usage: tsx observe.ts|write.ts [--iterations n] [--warmups n] [--jsonl]",
        );

      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }

  return options;
}

export function upstreamRevision(): string {
  try {
    return execFileSync(
      "git",
      ["-C", upstreamInstantRoot, "rev-parse", "--short", "HEAD"],
      {
        encoding: "utf8",
      },
    ).trim();
  } catch {
    return "unknown";
  }
}

export function loadFixture(name: "zeneca" | "movies") {
  const fixtureRoot = resolve(upstreamCoreRoot, "__tests__/src/data", name);
  const attrsPath = resolve(fixtureRoot, "attrs.json");
  const triplesPath = resolve(fixtureRoot, "triples.json");

  if (!existsSync(attrsPath) || !existsSync(triplesPath)) {
    throw new Error(`Missing upstream fixture: ${name}`);
  }

  const attrsText = readFileSync(attrsPath, "utf8");
  const triplesText = readFileSync(triplesPath, "utf8");
  const attrs = normalizeAttrs(JSON.parse(attrsText));
  const triples = JSON.parse(triplesText) as Triple[];
  const attrsStore = new AttrsStoreClass(attrs, null);
  const store = createStore(attrsStore, triples);

  return {
    name,
    attrs,
    attrsStore,
    store,
    triples,
    fixtureHash: sha256(`${attrsText}\n${triplesText}`),
  };
}

export function createContext(
  attrs: Record<string, InstantAttr>,
  triples: Triple[],
) {
  const attrsStore = new AttrsStoreClass(attrs, null);
  return {
    attrsStore,
    store: createStore(attrsStore, triples),
  };
}

export function createEmptyContext(attrs: Record<string, InstantAttr>) {
  return createContext(attrs, []);
}

export function cloneTriples(triples: Triple[]): Triple[] {
  return triples.map(([e, a, v, t]) => [e, a, cloneValue(v), t]);
}

export function normalizeAttrs(input: unknown): Record<string, InstantAttr> {
  if (Array.isArray(input)) {
    return Object.fromEntries(input.map((attr) => [attr.id, attr]));
  }
  return input as Record<string, InstantAttr>;
}

export function createGeneratedGraph(targetTriples: number) {
  const attrs = generatedAttrs();
  const attr = attrLookup(attrs);
  const triples: Triple[] = [];
  let createdAt = 1_780_000_000_000;
  let projectIndex = 0;
  const users = Array.from({ length: 50 }, (_, index) => `user-${index}`);

  for (const userID of users) {
    addEntity(triples, attr, "users", userID, createdAt++);
    addBlob(
      triples,
      attr,
      "users",
      userID,
      "email",
      `${userID}@example.test`,
      createdAt++,
    );
    addBlob(
      triples,
      attr,
      "users",
      userID,
      "displayName",
      `Benchmark User ${userID}`,
      createdAt++,
    );
  }

  while (triples.length < targetTriples) {
    const projectID = `project-${projectIndex}`;
    const ownerID = users[projectIndex % users.length];
    addEntity(triples, attr, "projects", projectID, createdAt++);
    addBlob(
      triples,
      attr,
      "projects",
      projectID,
      "title",
      `Project ${projectIndex}`,
      createdAt++,
    );
    addBlob(
      triples,
      attr,
      "projects",
      projectID,
      "order",
      projectIndex,
      createdAt++,
    );
    addRef(triples, attr, "projects", projectID, "owner", ownerID, createdAt++);

    for (
      let todoIndex = 0;
      todoIndex < 8 && triples.length < targetTriples;
      todoIndex++
    ) {
      const todoID = `todo-${projectIndex}-${todoIndex}`;
      const assigneeID = users[(projectIndex + todoIndex) % users.length];
      addEntity(triples, attr, "todos", todoID, createdAt++);
      addBlob(
        triples,
        attr,
        "todos",
        todoID,
        "title",
        `Todo ${projectIndex}.${todoIndex}`,
        createdAt++,
      );
      addBlob(
        triples,
        attr,
        "todos",
        todoID,
        "status",
        todoIndex % 3 === 0 ? "done" : "open",
        createdAt++,
      );
      addBlob(
        triples,
        attr,
        "todos",
        todoID,
        "priority",
        todoIndex % 10,
        createdAt++,
      );
      addBlob(
        triples,
        attr,
        "todos",
        todoID,
        "metadata",
        { lane: todoIndex % 4, audit: { touched: projectIndex + todoIndex } },
        createdAt++,
      );
      addRef(
        triples,
        attr,
        "projects",
        projectID,
        "todos",
        todoID,
        createdAt++,
      );
      addRef(
        triples,
        attr,
        "todos",
        todoID,
        "assignees",
        assigneeID,
        createdAt++,
      );

      const commentID = `comment-${projectIndex}-${todoIndex}`;
      addEntity(triples, attr, "comments", commentID, createdAt++);
      addBlob(
        triples,
        attr,
        "comments",
        commentID,
        "body",
        `Comment ${projectIndex}.${todoIndex}`,
        createdAt++,
      );
      addBlob(
        triples,
        attr,
        "comments",
        commentID,
        "index",
        todoIndex,
        createdAt++,
      );
      addRef(
        triples,
        attr,
        "todos",
        todoID,
        "comments",
        commentID,
        createdAt++,
      );
      addRef(
        triples,
        attr,
        "comments",
        commentID,
        "author",
        assigneeID,
        createdAt++,
      );
    }

    if (projectIndex % 5 === 0) {
      const fileID = `file-${projectIndex}`;
      addEntity(triples, attr, "$files", fileID, createdAt++);
      addBlob(
        triples,
        attr,
        "$files",
        fileID,
        "name",
        `project-${projectIndex}.txt`,
        createdAt++,
      );
      addBlob(
        triples,
        attr,
        "$files",
        fileID,
        "size",
        projectIndex * 128,
        createdAt++,
      );
      addRef(triples, attr, "$files", fileID, "owner", ownerID, createdAt++);
    }

    if (projectIndex % 10 === 0) {
      const chunkID = `stream-chunk-${projectIndex}`;
      addEntity(triples, attr, "$streamChunks", chunkID, createdAt++);
      addBlob(
        triples,
        attr,
        "$streamChunks",
        chunkID,
        "streamID",
        `project-${projectIndex}`,
        createdAt++,
      );
      addBlob(
        triples,
        attr,
        "$streamChunks",
        chunkID,
        "index",
        projectIndex / 10,
        createdAt++,
      );
      addBlob(
        triples,
        attr,
        "$streamChunks",
        chunkID,
        "text",
        `Chunk ${projectIndex}`,
        createdAt++,
      );
    }

    projectIndex += 1;
  }

  return {
    name: `generated-linked-${targetTriples}`,
    attrs,
    triples,
    entityCounts: {
      users: users.length,
      projects: projectIndex,
    },
    fixtureHash: stableHash({
      attrs,
      tripleCount: triples.length,
      first: triples[0],
      last: triples.at(-1),
    }),
  };
}

export async function benchmarkCase<Prepared>(
  options: BenchmarkOptions,
  benchmark: BenchmarkCase<Prepared>,
): Promise<BenchmarkMetric> {
  let lastResult: BenchmarkCaseResult | undefined;

  for (let index = 0; index < options.warmups; index++) {
    const prepared = benchmark.prepare
      ? benchmark.prepare()
      : (undefined as Prepared);
    lastResult = benchmark.run(prepared);
  }

  const samples: BenchmarkSample[] = [];
  for (let iteration = 0; iteration < options.iterations; iteration++) {
    const prepared = benchmark.prepare
      ? benchmark.prepare()
      : (undefined as Prepared);
    const memoryBeforeBytes = process.memoryUsage().heapUsed;
    const startedAt = process.hrtime.bigint();
    lastResult = benchmark.run(prepared);
    const durationNanoseconds = Number(process.hrtime.bigint() - startedAt);
    const memoryAfterBytes = process.memoryUsage().heapUsed;
    samples.push({
      iteration,
      durationNanoseconds,
      operationCount: lastResult.operationCount,
      resultCount: lastResult.resultCount,
      memoryBeforeBytes,
      memoryAfterBytes,
      memoryDeltaBytes: memoryAfterBytes - memoryBeforeBytes,
    });
  }

  if (!lastResult) {
    throw new Error(`Benchmark did not produce a result: ${benchmark.name}`);
  }

  return metricFromSamples(benchmark, lastResult, samples);
}

export async function benchmarkSuite(
  suite: string,
  options: BenchmarkOptions,
  cases: BenchmarkCase<any>[],
): Promise<BenchmarkRun> {
  const metrics: BenchmarkMetric[] = [];
  for (const benchmark of cases) {
    metrics.push(await benchmarkCase(options, benchmark));
  }

  return {
    suite,
    side: "typescript",
    upstreamRevision: upstreamRevision(),
    nodeVersion: process.version,
    platform: process.platform,
    arch: process.arch,
    iterations: options.iterations,
    warmups: options.warmups,
    timestampMs: Date.now(),
    metrics,
  };
}

export function writeBenchmarkRun(run: BenchmarkRun, jsonl: boolean) {
  if (jsonl) {
    for (const metric of run.metrics) {
      console.log(JSON.stringify({ ...run, metrics: undefined, metric }));
    }
  } else {
    console.log(JSON.stringify(run, null, 2));
  }
}

export function assertBenchmark(
  condition: unknown,
  message: string,
): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

export function stableHash(value: unknown): string {
  return sha256(stableStringify(value));
}

function metricFromSamples(
  benchmark: BenchmarkCase<any>,
  result: BenchmarkCaseResult,
  samples: BenchmarkSample[],
): BenchmarkMetric {
  const durations = samples
    .map((sample) => sample.durationNanoseconds)
    .sort((a, b) => a - b);
  const averageNanoseconds =
    durations.reduce((total, duration) => total + duration, 0) /
    Math.max(1, durations.length);

  return {
    name: benchmark.name,
    description: benchmark.description,
    fixture: benchmark.fixture,
    fixtureHash: benchmark.fixtureHash,
    source: benchmark.source,
    unit: "nanoseconds",
    operationCount: result.operationCount,
    resultCount: result.resultCount,
    correctnessHash: stableHash(result.correctness),
    samples,
    minNanoseconds: durations[0] ?? 0,
    p50Nanoseconds: percentile(durations, 0.5),
    p95Nanoseconds: percentile(durations, 0.95),
    maxNanoseconds: durations.at(-1) ?? 0,
    averageNanoseconds,
  };
}

function percentile(sortedDurations: number[], fraction: number): number {
  if (sortedDurations.length === 0) return 0;
  const index = Math.min(
    sortedDurations.length - 1,
    Math.ceil((sortedDurations.length - 1) * fraction),
  );
  return sortedDurations[index];
}

function sha256(input: string): string {
  return createHash("sha256").update(input).digest("hex");
}

function stableStringify(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }
  const entries = Object.entries(value as Record<string, unknown>).sort(
    ([a], [b]) => a.localeCompare(b),
  );
  return `{${entries
    .map(([key, item]) => `${JSON.stringify(key)}:${stableStringify(item)}`)
    .join(",")}}`;
}

function cloneValue(value: unknown): unknown {
  if (value === null || typeof value !== "object") return value;
  return JSON.parse(JSON.stringify(value));
}

function generatedAttrs(): Record<string, InstantAttr> {
  const attrs: InstantAttr[] = [
    blobAttr("users", "id", {
      unique: true,
      indexed: true,
      checkedDataType: "string",
    }),
    blobAttr("users", "email", {
      unique: true,
      indexed: true,
      checkedDataType: "string",
    }),
    blobAttr("users", "displayName", { checkedDataType: "string" }),
    blobAttr("projects", "id", {
      unique: true,
      indexed: true,
      checkedDataType: "string",
    }),
    blobAttr("projects", "title", { checkedDataType: "string" }),
    blobAttr("projects", "order", { indexed: true, checkedDataType: "number" }),
    refAttr("projects", "owner", "users", "ownedProjects", {
      cardinality: "one",
      unique: false,
    }),
    refAttr("projects", "todos", "todos", "project", {
      cardinality: "many",
      unique: true,
    }),
    blobAttr("todos", "id", {
      unique: true,
      indexed: true,
      checkedDataType: "string",
    }),
    blobAttr("todos", "title", { checkedDataType: "string" }),
    blobAttr("todos", "status", { indexed: true, checkedDataType: "string" }),
    blobAttr("todos", "priority", { indexed: true, checkedDataType: "number" }),
    blobAttr("todos", "metadata"),
    refAttr("todos", "assignees", "users", "assignedTodos", {
      cardinality: "many",
    }),
    refAttr("todos", "comments", "comments", "todo", {
      cardinality: "many",
      unique: true,
    }),
    blobAttr("comments", "id", {
      unique: true,
      indexed: true,
      checkedDataType: "string",
    }),
    blobAttr("comments", "body", { checkedDataType: "string" }),
    blobAttr("comments", "index", { checkedDataType: "number" }),
    refAttr("comments", "author", "users", "comments", { cardinality: "one" }),
    blobAttr("$files", "id", {
      unique: true,
      indexed: true,
      checkedDataType: "string",
    }),
    blobAttr("$files", "name", { checkedDataType: "string" }),
    blobAttr("$files", "size", { checkedDataType: "number" }),
    refAttr("$files", "owner", "users", "files", { cardinality: "one" }),
    blobAttr("$streamChunks", "id", {
      unique: true,
      indexed: true,
      checkedDataType: "string",
    }),
    blobAttr("$streamChunks", "streamID", {
      indexed: true,
      checkedDataType: "string",
    }),
    blobAttr("$streamChunks", "index", { checkedDataType: "number" }),
    blobAttr("$streamChunks", "text", { checkedDataType: "string" }),
  ];
  return Object.fromEntries(attrs.map((attr) => [attr.id, attr]));
}

function blobAttr(
  entity: string,
  label: string,
  options: {
    unique?: boolean;
    indexed?: boolean;
    checkedDataType?: InstantAttr["checked-data-type"];
  } = {},
): InstantAttr {
  return {
    id: `attr:${entity}:${label}`,
    "value-type": "blob",
    cardinality: "one",
    "forward-identity": [`ident:${entity}:${label}`, entity, label],
    "unique?": Boolean(options.unique),
    "index?": Boolean(options.indexed),
    ...(options.checkedDataType
      ? { "checked-data-type": options.checkedDataType }
      : {}),
  };
}

function refAttr(
  fromEntity: string,
  label: string,
  toEntity: string,
  reverseLabel: string,
  options: { cardinality?: "one" | "many"; unique?: boolean } = {},
): InstantAttr {
  return {
    id: `attr:${fromEntity}:${label}`,
    "value-type": "ref",
    cardinality: options.cardinality ?? "many",
    "forward-identity": [`ident:${fromEntity}:${label}`, fromEntity, label],
    "reverse-identity": [
      `ident:${toEntity}:${reverseLabel}`,
      toEntity,
      reverseLabel,
    ],
    "unique?": Boolean(options.unique),
    "index?": false,
  };
}

function attrLookup(attrs: Record<string, InstantAttr>) {
  const byEntityAndLabel = new Map<string, string>();
  for (const attr of Object.values(attrs)) {
    const [, entity, label] = attr["forward-identity"];
    byEntityAndLabel.set(`${entity}.${label}`, attr.id);
  }
  return (entity: string, label: string) => {
    const attrID = byEntityAndLabel.get(`${entity}.${label}`);
    if (!attrID) throw new Error(`Missing generated attr: ${entity}.${label}`);
    return attrID;
  };
}

function addEntity(
  triples: Triple[],
  attr: (entity: string, label: string) => string,
  entity: string,
  id: string,
  createdAt: number,
) {
  addBlob(triples, attr, entity, id, "id", id, createdAt);
}

function addBlob(
  triples: Triple[],
  attr: (entity: string, label: string) => string,
  entity: string,
  id: string,
  label: string,
  value: unknown,
  createdAt: number,
) {
  triples.push([id, attr(entity, label), value, createdAt]);
}

function addRef(
  triples: Triple[],
  attr: (entity: string, label: string) => string,
  entity: string,
  id: string,
  label: string,
  value: string,
  createdAt: number,
) {
  triples.push([id, attr(entity, label), value, createdAt]);
}
