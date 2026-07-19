import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const crossSDKBenchmarkContract = {
  version: 1,
  entityCount: 1_000,
  projectCount: 100,
  todosPerProject: 10,
  scalarUpdateCount: 10_000,
  storageMetadataCount: 100,
  streamChunkCount: 1_000,
  metricNames: [
    "transaction-transform.scalar",
    "triple-insert.todos",
    "triple-update.todos",
    "triple-retract.todos",
    "query-materialization.flat",
    "query-materialization.nested",
    "query-materialization.reverse",
    "high-bandwidth.scalar-updates",
    "high-bandwidth.linked-writes",
    "storage-metadata.query",
    "stream-write.chunks",
    "stream-read.chunks",
  ],
} as const;

interface BenchmarkSample {
  iteration: number;
  durationNanoseconds: number;
  operationCount?: number;
  resultCount?: number;
}

interface BenchmarkMetric {
  name: string;
  unit: "nanoseconds";
  samples: BenchmarkSample[];
  minNanoseconds: number;
  p50Nanoseconds: number;
  p95Nanoseconds: number;
  maxNanoseconds: number;
  averageNanoseconds: number;
}

export interface CrossSDKCoreBenchmarkResult {
  suite: "cross-sdk-core";
  sdk: "typescript";
  contractVersion: 1;
  coreVersion: string;
  iterations: number;
  timestampMs: number;
  ok: boolean;
  metrics: BenchmarkMetric[];
}

export async function runCrossSDKCoreBenchmark(
  iterations = integerArgument("--iterations", 5),
): Promise<CrossSDKCoreBenchmarkResult> {
  assert.ok(iterations > 0, "Iterations must be greater than zero.");
  const core = await loadCoreInternals();
  const samples = new Map<string, BenchmarkSample[]>();
  const record = (
    name: string,
    iteration: number,
    durationNanoseconds: number,
    operationCount?: number,
    resultCount?: number,
  ) => {
    const metricSamples = samples.get(name) ?? [];
    metricSamples.push({
      iteration,
      durationNanoseconds,
      ...(operationCount === undefined ? {} : { operationCount }),
      ...(resultCount === undefined ? {} : { resultCount }),
    });
    samples.set(name, metricSamples);
  };

  for (let iteration = 0; iteration < iterations; iteration += 1) {
    const transformAttrs = core.makeAttrsStore();
    const transformChunks = todoChunks(core.tx);
    const transformDuration = measured(() => {
      core.transform({ attrsStore: transformAttrs, schema: core.schema }, transformChunks);
    });
    record(
      "transaction-transform.scalar",
      iteration,
      transformDuration,
      crossSDKBenchmarkContract.entityCount,
    );

    const insert = prepareTransaction(core, todoChunks(core.tx));
    const insertDuration = measured(() => {
      insert.context = core.transact(insert.context.store, insert.context.attrsStore, insert.steps);
    });
    assert.equal(queryTodos(core, insert.context).length, crossSDKBenchmarkContract.entityCount);
    record(
      "triple-insert.todos",
      iteration,
      insertDuration,
      insert.steps.length,
      crossSDKBenchmarkContract.entityCount * 4,
    );

    const updateChunks = Array.from(
      { length: crossSDKBenchmarkContract.entityCount },
      (_, index) => core.tx.todos[todoID(index)].update({ text: `Updated ${index}` }),
    );
    const updateSteps = core.transform(insert.context, updateChunks);
    const updateDuration = measured(() => {
      insert.context = core.transact(
        insert.context.store,
        insert.context.attrsStore,
        updateSteps,
      );
    });
    const updated = queryTodos(core, insert.context);
    assert.equal(updated.length, crossSDKBenchmarkContract.entityCount);
    assert.equal(updated[0]?.text, "Updated 0");
    record(
      "triple-update.todos",
      iteration,
      updateDuration,
      updateSteps.length,
      updated.length,
    );

    const retractChunks = Array.from(
      { length: crossSDKBenchmarkContract.entityCount },
      (_, index) => core.tx.todos[todoID(index)].delete(),
    );
    const retractSteps = core.transform(insert.context, retractChunks);
    const retractDuration = measured(() => {
      insert.context = core.transact(
        insert.context.store,
        insert.context.attrsStore,
        retractSteps,
      );
    });
    assert.equal(queryTodos(core, insert.context).length, 0);
    record(
      "triple-retract.todos",
      iteration,
      retractDuration,
      retractSteps.length,
      0,
    );

    const flatContext = seededContext(core, todoChunks(core.tx));
    let flat: any[] = [];
    const flatDuration = measured(() => {
      flat = queryTodos(core, flatContext);
    });
    assert.equal(flat.length, crossSDKBenchmarkContract.entityCount);
    record("query-materialization.flat", iteration, flatDuration, undefined, flat.length);

    const linkedContext = seededContext(core, linkedChunks(core.tx, true));
    let nested: any[] = [];
    const nestedDuration = measured(() => {
      nested = core.query(linkedContext, {
        todos: { project: {} },
      }).data.todos;
    });
    assert.equal(nested.length, crossSDKBenchmarkContract.entityCount);
    assert.ok(nested.every((todo) => todo.project?.id));
    record(
      "query-materialization.nested",
      iteration,
      nestedDuration,
      undefined,
      nested.length,
    );

    let reverse: any[] = [];
    const reverseDuration = measured(() => {
      reverse = core.query(linkedContext, {
        projects: { todos: {} },
      }).data.projects;
    });
    assert.equal(reverse.length, crossSDKBenchmarkContract.projectCount);
    assert.ok(
      reverse.every(
        (project) => project.todos.length === crossSDKBenchmarkContract.todosPerProject,
      ),
    );
    record(
      "query-materialization.reverse",
      iteration,
      reverseDuration,
      undefined,
      reverse.length,
    );

    let scalarContext = seededContext(core, [todoChunk(core.tx, 0)]);
    const scalarDuration = measured(() => {
      for (let index = 0; index < crossSDKBenchmarkContract.scalarUpdateCount; index += 1) {
        const steps = core.transform(scalarContext, [
          core.tx.todos[todoID(0)].update({ text: `Scalar ${index}` }),
        ]);
        scalarContext = core.transact(
          scalarContext.store,
          scalarContext.attrsStore,
          steps,
        );
      }
    });
    const scalar = queryTodos(core, scalarContext);
    assert.equal(
      scalar[0]?.text,
      `Scalar ${crossSDKBenchmarkContract.scalarUpdateCount - 1}`,
    );
    record(
      "high-bandwidth.scalar-updates",
      iteration,
      scalarDuration,
      crossSDKBenchmarkContract.scalarUpdateCount,
      scalar.length,
    );

    const unlinkedContext = seededContext(core, linkedChunks(core.tx, false));
    const links = Array.from(
      { length: crossSDKBenchmarkContract.entityCount },
      (_, index) =>
        core.tx.todos[todoID(index)].link({
          project: projectID(Math.floor(index / crossSDKBenchmarkContract.todosPerProject)),
        }),
    );
    const linkSteps = core.transform(unlinkedContext, links);
    let linkedWriteContext = unlinkedContext;
    const linkedDuration = measured(() => {
      linkedWriteContext = core.transact(
        unlinkedContext.store,
        unlinkedContext.attrsStore,
        linkSteps,
      );
    });
    const linkedProjects = core.query(linkedWriteContext, {
      projects: { todos: {} },
    }).data.projects;
    assert.equal(
      linkedProjects.reduce((count, project) => count + project.todos.length, 0),
      crossSDKBenchmarkContract.entityCount,
    );
    record(
      "high-bandwidth.linked-writes",
      iteration,
      linkedDuration,
      linkSteps.length,
      linkedProjects.length,
    );

    const storageContext = seededContext(core, storageChunks(core.tx));
    let files: any[] = [];
    const storageDuration = measured(() => {
      files = core.query(storageContext, { benchmarkFiles: {} }).data.benchmarkFiles;
    });
    assert.equal(files.length, crossSDKBenchmarkContract.storageMetadataCount);
    record("storage-metadata.query", iteration, storageDuration, undefined, files.length);

    const stream = prepareTransaction(core, streamChunks(core.tx));
    const streamWriteDuration = measured(() => {
      stream.context = core.transact(stream.context.store, stream.context.attrsStore, stream.steps);
    });
    record(
      "stream-write.chunks",
      iteration,
      streamWriteDuration,
      stream.steps.length,
      crossSDKBenchmarkContract.streamChunkCount,
    );
    let chunks: any[] = [];
    const streamReadDuration = measured(() => {
      chunks = core.query(stream.context, { benchmarkStreamChunks: {} })
        .data.benchmarkStreamChunks;
    });
    assert.equal(chunks.length, crossSDKBenchmarkContract.streamChunkCount);
    record("stream-read.chunks", iteration, streamReadDuration, undefined, chunks.length);
  }

  const metrics = crossSDKBenchmarkContract.metricNames.map((name) =>
    benchmarkMetric(name, samples.get(name) ?? [])
  );
  return {
    suite: "cross-sdk-core",
    sdk: "typescript",
    contractVersion: 1,
    coreVersion: core.version,
    iterations,
    timestampMs: Date.now(),
    ok: metrics.every((metric) => metric.samples.length === iterations),
    metrics,
  };
}

async function loadCoreInternals() {
  const packageEntry = fileURLToPath(import.meta.resolve("@instantdb/core"));
  const dist = dirname(packageEntry);
  const module = async (path: string) => import(pathToFileURL(resolve(dist, path)).href);
  const [schemaModule, txModule, transformModule, storeModule, queryModule, linkModule] =
    await Promise.all([
      module("schema.js"),
      module("instatx.js"),
      module("instaml.js"),
      module("store.js"),
      module("instaql.js"),
      module("utils/linkIndex.js"),
    ]);
  const schema = schemaModule.i.schema({
    entities: {
      todos: schemaModule.i.entity({
        text: schemaModule.i.string(),
        isCompleted: schemaModule.i.boolean(),
        createdAt: schemaModule.i.date(),
      }),
      projects: schemaModule.i.entity({ title: schemaModule.i.string() }),
      benchmarkFiles: schemaModule.i.entity({
        path: schemaModule.i.string(),
        size: schemaModule.i.number(),
      }),
      benchmarkStreamChunks: schemaModule.i.entity({
        index: schemaModule.i.number(),
        payload: schemaModule.i.json(),
      }),
    },
    links: {
      projectTodos: {
        forward: { on: "todos", has: "one", label: "project" },
        reverse: { on: "projects", has: "many", label: "todos" },
      },
    },
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
    version: (await import("@instantdb/core/package.json", { with: { type: "json" } }))
      .default.version as string,
  };
}

function prepareTransaction(core: any, chunks: any[]) {
  const attrsStore = core.makeAttrsStore();
  const steps = core.transform({ attrsStore, schema: core.schema }, chunks);
  return {
    context: {
      store: core.createStore(attrsStore, [], true, true),
      attrsStore,
      schema: core.schema,
    },
    steps,
  };
}

function seededContext(core: any, chunks: any[]) {
  const prepared = prepareTransaction(core, chunks);
  return {
    ...core.transact(prepared.context.store, prepared.context.attrsStore, prepared.steps),
    schema: core.schema,
  };
}

function todoChunks(tx: any): any[] {
  return Array.from(
    { length: crossSDKBenchmarkContract.entityCount },
    (_, index) => todoChunk(tx, index),
  );
}

function todoChunk(tx: any, index: number): any {
  return tx.todos[todoID(index)].update({
    text: `Todo ${index}`,
    isCompleted: false,
    createdAt: fixedDate(index),
  });
}

function linkedChunks(tx: any, includeLinks: boolean): any[] {
  const projects = Array.from(
    { length: crossSDKBenchmarkContract.projectCount },
    (_, index) => tx.projects[projectID(index)].update({ title: `Project ${index}` }),
  );
  const todos = Array.from(
    { length: crossSDKBenchmarkContract.entityCount },
    (_, index) => {
      const todo = todoChunk(tx, index);
      return includeLinks
        ? todo.link({
            project: projectID(
              Math.floor(index / crossSDKBenchmarkContract.todosPerProject),
            ),
          })
        : todo;
    },
  );
  return [...projects, ...todos];
}

function storageChunks(tx: any): any[] {
  return Array.from(
    { length: crossSDKBenchmarkContract.storageMetadataCount },
    (_, index) =>
      tx.benchmarkFiles[`file-${index}`].update({
        path: `bench/file-${index}.txt`,
        size: index + 1,
      }),
  );
}

function streamChunks(tx: any): any[] {
  return Array.from(
    { length: crossSDKBenchmarkContract.streamChunkCount },
    (_, index) =>
      tx.benchmarkStreamChunks[`chunk-${index}`].update({
        index,
        payload: { index },
      }),
  );
}

function queryTodos(core: any, context: any): any[] {
  return core.query(context, { todos: {} }).data.todos;
}

function benchmarkMetric(name: string, samples: BenchmarkSample[]): BenchmarkMetric {
  const durations = samples.map((sample) => sample.durationNanoseconds).sort((a, b) => a - b);
  return {
    name,
    unit: "nanoseconds",
    samples,
    minNanoseconds: durations[0] ?? 0,
    p50Nanoseconds: percentile(durations, 0.5),
    p95Nanoseconds: percentile(durations, 0.95),
    maxNanoseconds: durations.at(-1) ?? 0,
    averageNanoseconds:
      durations.reduce((sum, duration) => sum + duration, 0) / Math.max(durations.length, 1),
  };
}

function percentile(sorted: number[], fraction: number): number {
  if (sorted.length === 0) return 0;
  const index = Math.ceil((sorted.length - 1) * fraction);
  return sorted[Math.min(index, sorted.length - 1)];
}

function measured(operation: () => void): number {
  const start = process.hrtime.bigint();
  operation();
  return Number(process.hrtime.bigint() - start);
}

function integerArgument(name: string, fallback: number): number {
  const index = process.argv.indexOf(name);
  if (index < 0) return fallback;
  const value = Number(process.argv[index + 1]);
  assert.ok(Number.isSafeInteger(value) && value > 0, `${name} must be a positive integer.`);
  return value;
}

function todoID(index: number): string {
  return `todo-${index}`;
}

function projectID(index: number): string {
  return `project-${index}`;
}

function fixedDate(index: number): Date {
  return new Date(1_700_000_000_000 + index);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = await runCrossSDKCoreBenchmark();
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}
