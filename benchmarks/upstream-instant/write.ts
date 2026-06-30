import * as instaml from "../../upstream/instant/client/packages/core/src/instaml.ts";
import {
  getOps,
  tx,
} from "../../upstream/instant/client/packages/core/src/instatx.ts";
import {
  allMapValues,
  transact,
} from "../../upstream/instant/client/packages/core/src/store.ts";

import {
  benchmarkSuite,
  cloneTriples,
  createContext,
  createEmptyContext,
  createGeneratedGraph,
  parseBenchmarkOptions,
  sourceLabels,
  stableHash,
  writeBenchmarkRun,
  type BenchmarkCase,
  type Triple,
} from "./shared.ts";

const options = parseBenchmarkOptions(process.argv.slice(2), {
  iterations: 10,
  warmups: 3,
  jsonl: false,
});

const generated1k = createGeneratedGraph(1_000);
const generated10k = createGeneratedGraph(10_000);
const generated50k = createGeneratedGraph(50_000);
const mixedChunks1k = buildMixedChunks(1_000);
const createLinkChunks1k = buildCreateLinkChunks(1_000);
const transformContext = createEmptyContext(generated10k.attrs);
const createLinkSteps1k = instaml.transform(
  { attrsStore: transformContext.attrsStore, stores: [transformContext.store] },
  createLinkChunks1k,
);
const insertSteps1k = addTripleSteps(generated1k.triples);
const insertSteps10k = addTripleSteps(generated10k.triples);
const insertSteps50k = addTripleSteps(generated50k.triples);
const mergeSteps500 = metadataMergeSteps(
  generated10k.triples,
  generated10k.attrs,
  500,
);
const retractSteps500 = refRetractSteps(
  generated10k.triples,
  generated10k.attrs,
  "projects",
  "todos",
  500,
);
const deleteSteps500 = entityDeleteSteps(
  generated10k.triples,
  generated10k.attrs,
  "todos",
  500,
);

const cases: BenchmarkCase<any>[] = [
  {
    name: "write.transaction-builder.mixed-1k",
    description:
      "Build create, update, link, unlink, merge, and delete chunks through Instant tx proxies.",
    fixture: "generated-mixed-ops",
    fixtureHash: stableHash({ count: 1_000, shape: "mixed tx chunks" }),
    source: sourceLabels.instatx,
    run: () => {
      const chunks = buildMixedChunks(1_000);
      const opCount = chunks.flatMap((chunk) => getOps(chunk)).length;
      return {
        operationCount: opCount,
        resultCount: chunks.length,
        correctness: {
          chunks: chunks.length,
          opCount,
          first: getOps(chunks[0]),
          last: getOps(chunks.at(-1)),
        },
      };
    },
  },
  {
    name: "write.instaml-transform.mixed-1k",
    description:
      "Lower mixed transaction chunks into upstream tx-steps with warm attrs.",
    fixture: generated10k.name,
    fixtureHash: generated10k.fixtureHash,
    source: sourceLabels.instaml,
    prepare: () => createEmptyContext(generated10k.attrs),
    run: ({ attrsStore, store }) => {
      const steps = instaml.transform(
        { attrsStore, stores: [store] },
        mixedChunks1k,
      );
      return {
        operationCount: mixedChunks1k.flatMap((chunk) => getOps(chunk)).length,
        resultCount: steps.length,
        correctness: {
          steps: steps.length,
          first: steps[0],
          last: steps.at(-1),
          hash: stableHash(steps.slice(0, 25)),
        },
      };
    },
  },
  {
    name: "write.store-transact.create-link-1k",
    description:
      "Apply a 1k mixed create/link tx-step batch to an empty local store.",
    fixture: generated10k.name,
    fixtureHash: generated10k.fixtureHash,
    source: sourceLabels.store,
    prepare: () => createEmptyContext(generated10k.attrs),
    run: ({ store, attrsStore }) => {
      const result = transact(store, attrsStore, createLinkSteps1k);
      const tripleCount = allMapValues(result.store.eav, 3).length;
      return {
        operationCount: createLinkSteps1k.length,
        resultCount: tripleCount,
        correctness: {
          tripleCount,
          firstProjectTriples: allMapValues(
            result.store.eav.get("write-project-0"),
            2,
          ),
        },
      };
    },
  },
  {
    name: "write.store-triple-insert.generated-1k",
    description: "Apply generated add-triple tx-steps at the 1k tier.",
    fixture: generated1k.name,
    fixtureHash: generated1k.fixtureHash,
    source: sourceLabels.store,
    prepare: () => createEmptyContext(generated1k.attrs),
    run: ({ store, attrsStore }) => {
      const result = transact(store, attrsStore, insertSteps1k);
      const tripleCount = allMapValues(result.store.eav, 3).length;
      return {
        operationCount: insertSteps1k.length,
        resultCount: tripleCount,
        correctness: { tripleCount, expected: generated1k.triples.length },
      };
    },
  },
  {
    name: "write.store-triple-insert.generated-10k",
    description: "Apply generated add-triple tx-steps at the 10k tier.",
    fixture: generated10k.name,
    fixtureHash: generated10k.fixtureHash,
    source: sourceLabels.store,
    prepare: () => createEmptyContext(generated10k.attrs),
    run: ({ store, attrsStore }) => {
      const result = transact(store, attrsStore, insertSteps10k);
      const tripleCount = allMapValues(result.store.eav, 3).length;
      return {
        operationCount: insertSteps10k.length,
        resultCount: tripleCount,
        correctness: { tripleCount, expected: generated10k.triples.length },
      };
    },
  },
  {
    name: "write.store-triple-insert.generated-50k",
    description: "Apply generated add-triple tx-steps at the 50k tier.",
    fixture: generated50k.name,
    fixtureHash: generated50k.fixtureHash,
    source: sourceLabels.store,
    prepare: () => createEmptyContext(generated50k.attrs),
    run: ({ store, attrsStore }) => {
      const result = transact(store, attrsStore, insertSteps50k);
      const tripleCount = allMapValues(result.store.eav, 3).length;
      return {
        operationCount: insertSteps50k.length,
        resultCount: tripleCount,
        correctness: { tripleCount, expected: generated50k.triples.length },
      };
    },
  },
  {
    name: "write.store-merge.metadata-500",
    description:
      "Deep-merge nested todo metadata without replacing the whole store.",
    fixture: generated10k.name,
    fixtureHash: generated10k.fixtureHash,
    source: sourceLabels.store,
    prepare: () =>
      createContext(generated10k.attrs, cloneTriples(generated10k.triples)),
    run: ({ store, attrsStore }) => {
      const result = transact(store, attrsStore, mergeSteps500);
      const todoMetadataAttr = attrID(generated10k.attrs, "todos", "metadata");
      const firstMerged = allMapValues(
        result.store.eav.get("todo-0-0")?.get(todoMetadataAttr),
        1,
      );
      return {
        operationCount: mergeSteps500.length,
        resultCount: firstMerged.length,
        correctness: {
          firstMerged,
          hash: stableHash(firstMerged),
        },
      };
    },
  },
  {
    name: "write.store-retract-links.projects-todos-500",
    description: "Retract project-to-todo links from a seeded graph.",
    fixture: generated10k.name,
    fixtureHash: generated10k.fixtureHash,
    source: sourceLabels.store,
    prepare: () =>
      createContext(generated10k.attrs, cloneTriples(generated10k.triples)),
    run: ({ store, attrsStore }) => {
      const result = transact(store, attrsStore, retractSteps500);
      const projectsTodosAttr = attrID(generated10k.attrs, "projects", "todos");
      const remainingLinks = allMapValues(
        result.store.aev.get(projectsTodosAttr),
        2,
      ).length;
      return {
        operationCount: retractSteps500.length,
        resultCount: remainingLinks,
        correctness: {
          remainingLinks,
          retracted: retractSteps500.length,
        },
      };
    },
  },
  {
    name: "write.store-delete.todos-500",
    description: "Delete seeded todo entities and their forward/reverse links.",
    fixture: generated10k.name,
    fixtureHash: generated10k.fixtureHash,
    source: sourceLabels.store,
    prepare: () =>
      createContext(generated10k.attrs, cloneTriples(generated10k.triples)),
    run: ({ store, attrsStore }) => {
      const result = transact(store, attrsStore, deleteSteps500);
      const remainingTodoIDs = allMapValues(
        result.store.aev.get(attrID(generated10k.attrs, "todos", "id")),
        2,
      ).length;
      return {
        operationCount: deleteSteps500.length,
        resultCount: remainingTodoIDs,
        correctness: {
          remainingTodoIDs,
          deleted: deleteSteps500.length,
        },
      };
    },
  },
];

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

async function main() {
  const run = await benchmarkSuite("upstream-instant-write", options, cases);
  writeBenchmarkRun(run, options.jsonl);
}

function buildMixedChunks(count: number) {
  const chunks: any[] = [];
  for (let index = 0; index < count; index++) {
    const projectID = `write-project-${index}`;
    const todoID = `write-todo-${index}`;
    const commentID = `write-comment-${index}`;
    const userID = `user-${index % 50}`;

    chunks.push(
      tx.projects[projectID]
        .create({ title: `Write project ${index}`, order: index })
        .link({ owner: userID, todos: todoID })
        .merge({ metadata: { revision: index } })
        .unlink({ todos: todoID }),
    );
    chunks.push(
      tx.todos[todoID]
        .update({
          title: `Write todo ${index}`,
          status: index % 2 === 0 ? "open" : "done",
          priority: index % 10,
          metadata: { lane: index % 4 },
        })
        .link({ assignees: userID })
        .merge({ metadata: { audit: { writer: index } } }),
    );
    chunks.push(
      tx.comments[commentID]
        .create({ body: `Comment ${index}`, index })
        .delete(),
    );
  }
  return chunks;
}

function buildCreateLinkChunks(count: number) {
  const chunks: any[] = [];
  for (let index = 0; index < count; index++) {
    const projectID = `write-project-${index}`;
    const todoID = `write-todo-${index}`;
    const userID = `user-${index % 50}`;
    chunks.push(
      tx.projects[projectID].create({
        title: `Write project ${index}`,
        order: index,
      }),
    );
    chunks.push(
      tx.todos[todoID].create({
        title: `Write todo ${index}`,
        status: "open",
        priority: index % 10,
        metadata: { lane: index % 4 },
      }),
    );
    chunks.push(tx.projects[projectID].link({ owner: userID, todos: todoID }));
    chunks.push(tx.todos[todoID].link({ assignees: userID }));
  }
  return chunks;
}

function addTripleSteps(triples: Triple[]) {
  return triples.map(([entityID, attr, value]) => [
    "add-triple",
    entityID,
    attr,
    value,
  ]);
}

function metadataMergeSteps(
  triples: Triple[],
  attrs: Record<string, any>,
  count: number,
) {
  const metadataAttr = attrID(attrs, "todos", "metadata");
  return triples
    .filter(([, attr]) => attr === metadataAttr)
    .slice(0, count)
    .map(([entityID], index) => [
      "deep-merge-triple",
      entityID,
      metadataAttr,
      {
        audit: {
          revision: index,
          status: "merged",
        },
      },
    ]);
}

function refRetractSteps(
  triples: Triple[],
  attrs: Record<string, any>,
  entity: string,
  label: string,
  count: number,
) {
  const refAttr = attrID(attrs, entity, label);
  return triples
    .filter(([, attr]) => attr === refAttr)
    .slice(0, count)
    .map(([entityID, attr, value]) => [
      "retract-triple",
      entityID,
      attr,
      value,
    ]);
}

function entityDeleteSteps(
  triples: Triple[],
  attrs: Record<string, any>,
  entity: string,
  count: number,
) {
  const idAttr = attrID(attrs, entity, "id");
  return triples
    .filter(([, attr]) => attr === idAttr)
    .slice(0, count)
    .map(([entityID]) => ["delete-entity", entityID, entity]);
}

function attrID(
  attrs: Record<string, any>,
  entity: string,
  label: string,
): string {
  const attr = Object.values(attrs).find((candidate: any) => {
    const [, candidateEntity, candidateLabel] = candidate["forward-identity"];
    return candidateEntity === entity && candidateLabel === label;
  }) as { id: string } | undefined;
  if (!attr) throw new Error(`Missing attr: ${entity}.${label}`);
  return attr.id;
}
