import instaql from "../../upstream/instant/client/packages/core/src/instaql.ts";
import { subscribeInfiniteQuery } from "../../upstream/instant/client/packages/core/src/infiniteQuery.ts";

import {
  assertBenchmark,
  benchmarkSuite,
  createContext,
  createGeneratedGraph,
  loadFixture,
  parseBenchmarkOptions,
  sourceLabels,
  stableHash,
  writeBenchmarkRun,
  type BenchmarkCase,
} from "./shared.ts";

const options = parseBenchmarkOptions(process.argv.slice(2), {
  iterations: 20,
  warmups: 5,
  jsonl: false,
});

const zeneca = loadFixture("zeneca");
const generated1k = createGeneratedGraph(1_000);
const generated10k = createGeneratedGraph(10_000);
const generated1kContext = createContext(
  generated1k.attrs,
  generated1k.triples,
);
const generated10kContext = createContext(
  generated10k.attrs,
  generated10k.triples,
);

const zenecaBigQuery = {
  users: {
    bookshelves: {
      books: {},
      users: {
        bookshelves: {},
      },
    },
  },
};

const linkedIncludeQuery = {
  projects: {
    owner: {},
    todos: {
      assignees: {},
      comments: {
        author: {},
      },
    },
    $: {
      first: 50,
      order: { order: "asc" },
    },
  },
};

const nestedWhereOrderFieldsQuery = {
  projects: {
    todos: {
      assignees: {
        $: { fields: ["email"] },
      },
      $: {
        where: {
          and: [{ status: "open" }, { priority: { $gte: 5 } }],
        },
        fields: ["title", "status", "priority"],
        order: { priority: "desc" },
      },
    },
    $: {
      where: { "todos.status": "open" },
      fields: ["title", "order"],
      order: { order: "asc" },
      first: 75,
    },
  },
};

const reverseLinkedQuery = {
  users: {
    assignedTodos: {
      project: {},
    },
    files: {},
    $: {
      first: 50,
      order: { email: "asc" },
    },
  },
};

const cases: BenchmarkCase<any>[] = [
  {
    name: "core.instaql.big-query.zeneca",
    description: "Upstream recursive linked query over the Zeneca fixture.",
    fixture: "zeneca",
    fixtureHash: zeneca.fixtureHash,
    source: `${sourceLabels.instaql}; upstream __tests__/src/instaql.bench.ts`,
    run: () => {
      const result = instaql(
        { store: zeneca.store, attrsStore: zeneca.attrsStore },
        zenecaBigQuery,
      );
      const users = result.data.users;
      assertBenchmark(
        users.length > 0,
        "Expected Zeneca big query to return users.",
      );
      return {
        resultCount: users.length,
        correctness: {
          users: users.length,
          nestedBookshelves: users.flatMap((user: any) => user.bookshelves)
            .length,
          hash: stableHash(users.slice(0, 3)),
        },
      };
    },
  },
  {
    name: "query.linked-include.generated-1k",
    description:
      "Forward includes across projects, todos, assignees, comments, and authors.",
    fixture: generated1k.name,
    fixtureHash: generated1k.fixtureHash,
    source: sourceLabels.instaql,
    run: () => {
      const result = instaql(generated1kContext, linkedIncludeQuery);
      const projects = result.data.projects;
      const todoCount = projects.flatMap(
        (project: any) => project.todos,
      ).length;
      assertBenchmark(
        projects.length > 0 && todoCount > 0,
        "Expected linked include query to return projects and todos.",
      );
      return {
        resultCount: todoCount,
        correctness: {
          projects: projects.length,
          todoCount,
          firstProject: projects[0]?.id,
          hash: stableHash(projects.slice(0, 5)),
        },
      };
    },
  },
  {
    name: "query.linked-include.generated-10k",
    description: "Forward includes at the 10k-triple tier.",
    fixture: generated10k.name,
    fixtureHash: generated10k.fixtureHash,
    source: sourceLabels.instaql,
    run: () => {
      const result = instaql(generated10kContext, linkedIncludeQuery);
      const projects = result.data.projects;
      const todoCount = projects.flatMap(
        (project: any) => project.todos,
      ).length;
      assertBenchmark(
        projects.length > 0 && todoCount > 0,
        "Expected 10k linked include query to return projects and todos.",
      );
      return {
        resultCount: todoCount,
        correctness: {
          projects: projects.length,
          todoCount,
          firstProject: projects[0]?.id,
          hash: stableHash(projects.slice(0, 5)),
        },
      };
    },
  },
  {
    name: "query.nested-where-order-fields.generated-10k",
    description:
      "Nested where, order, fields projection, and child include filtering.",
    fixture: generated10k.name,
    fixtureHash: generated10k.fixtureHash,
    source: sourceLabels.instaql,
    run: () => {
      const result = instaql(generated10kContext, nestedWhereOrderFieldsQuery);
      const projects = result.data.projects;
      const todoCount = projects.flatMap(
        (project: any) => project.todos,
      ).length;
      assertBenchmark(
        projects.length > 0 && todoCount > 0,
        "Expected nested where/order/fields query to return rows.",
      );
      return {
        resultCount: todoCount,
        correctness: {
          projects: projects.length,
          todoCount,
          projectedKeys: Object.keys(projects[0] ?? {}).sort(),
          hash: stableHash(projects.slice(0, 5)),
        },
      };
    },
  },
  {
    name: "query.reverse-linked.generated-10k",
    description:
      "Reverse link materialization from users to assigned todos and file metadata.",
    fixture: generated10k.name,
    fixtureHash: generated10k.fixtureHash,
    source: sourceLabels.instaql,
    run: () => {
      const result = instaql(generated10kContext, reverseLinkedQuery);
      const users = result.data.users;
      const assignedTodoCount = users.flatMap(
        (user: any) => user.assignedTodos,
      ).length;
      assertBenchmark(
        users.length > 0 && assignedTodoCount > 0,
        "Expected reverse linked query to return assigned todos.",
      );
      return {
        resultCount: assignedTodoCount,
        correctness: {
          users: users.length,
          assignedTodoCount,
          fileCount: users.flatMap((user: any) => user.files).length,
          hash: stableHash(users.slice(0, 5)),
        },
      };
    },
  },
  {
    name: "observe.subscription-fanout.synthetic-1k",
    description:
      "Dispatch one materialized query result to 1,000 observers without recomputing the query.",
    fixture: generated1k.name,
    fixtureHash: generated1k.fixtureHash,
    source: "synthetic observer dispatch around upstream InstaQL result",
    prepare: () => {
      const result = instaql(generated1kContext, linkedIncludeQuery);
      const observers = Array.from(
        { length: 1_000 },
        () => (value: unknown) => {
          if (!value) throw new Error("Observer received an empty value.");
        },
      );
      return { result, observers };
    },
    run: ({ result, observers }) => {
      for (const observer of observers) {
        observer(result);
      }
      return {
        operationCount: observers.length,
        resultCount: result.data.projects.length,
        correctness: {
          observers: observers.length,
          projects: result.data.projects.length,
          hash: stableHash(result.data.projects.slice(0, 3)),
        },
      };
    },
  },
  {
    name: "observe.infinite-query-control.5-pages",
    description:
      "Instant core infinite-query subscription manager over deterministic local pages.",
    fixture: generated1k.name,
    fixtureHash: generated1k.fixtureHash,
    source: sourceLabels.infiniteQuery,
    run: () => runInfiniteQueryControlBenchmark(),
  },
];

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

async function main() {
  const run = await benchmarkSuite("upstream-instant-observe", options, cases);
  writeBenchmarkRun(run, options.jsonl);
}

function runInfiniteQueryControlBenchmark() {
  const fakeDB = createFakeInfiniteDB(
    Array.from({ length: 200 }, (_, index) => ({
      id: `project-page-${index}`,
      order: index,
      title: `Project page ${index}`,
    })),
  );

  let callbackCount = 0;
  let lastResponse: any;
  const subscription = subscribeInfiniteQuery(
    fakeDB as any,
    {
      projects: {
        $: {
          limit: 25,
          order: { order: "asc" },
        },
      },
    },
    (response) => {
      callbackCount += 1;
      lastResponse = response;
    },
  );

  for (let page = 0; page < 5; page++) {
    subscription.loadNextPage();
  }
  subscription.unsubscribe();

  assertBenchmark(
    callbackCount > 0,
    "Expected infinite query to invoke callbacks.",
  );
  assertBenchmark(
    fakeDB.activeSubscriptions() === 0,
    "Expected infinite query unsubscribe to release every subscription.",
  );

  return {
    operationCount: fakeDB.totalSubscriptions(),
    resultCount: lastResponse?.data?.projects?.length ?? 0,
    correctness: {
      callbackCount,
      totalSubscriptions: fakeDB.totalSubscriptions(),
      activeSubscriptions: fakeDB.activeSubscriptions(),
      finalCount: lastResponse?.data?.projects?.length ?? 0,
      canLoadNextPage: Boolean(lastResponse?.canLoadNextPage),
      firstID: lastResponse?.data?.projects?.[0]?.id,
      lastID: lastResponse?.data?.projects?.at(-1)?.id,
    },
  };
}

function createFakeInfiniteDB(
  rows: Array<{ id: string; order: number; title: string }>,
) {
  let active = 0;
  let total = 0;

  return {
    subscribeQuery(
      fullQuery: Record<string, any>,
      callback: (response: any) => void,
    ) {
      total += 1;
      active += 1;
      const entity = Object.keys(fullQuery)[0];
      const query = fullQuery[entity] ?? {};
      const params = query.$ ?? {};
      const limit = params.limit ?? 25;
      const orderDirection =
        params.order?.order ?? params.order?.serverCreatedAt ?? "asc";
      const afterIndex = cursorIndex(params.after);
      const beforeIndex = cursorIndex(params.before);
      const afterInclusive = Boolean(params.afterInclusive);
      const beforeInclusive = Boolean(params.beforeInclusive);
      const page =
        orderDirection === "desc"
          ? reversePage(rows, afterIndex, limit)
          : forwardPage(
              rows,
              afterIndex,
              beforeIndex,
              afterInclusive,
              beforeInclusive,
              limit,
            );

      callback({
        error: undefined,
        data: { [entity]: page.rows },
        pageInfo: {
          [entity]: {
            startCursor: cursorFor(page.rows[0]),
            endCursor: cursorFor(page.rows.at(-1)),
            hasNextPage: page.hasNextPage,
            hasPreviousPage: false,
          },
        },
      });

      return () => {
        active -= 1;
      };
    },
    activeSubscriptions: () => active,
    totalSubscriptions: () => total,
  };
}

function forwardPage(
  rows: Array<{ id: string; order: number; title: string }>,
  afterIndex: number | null,
  beforeIndex: number | null,
  afterInclusive: boolean,
  beforeInclusive: boolean,
  limit: number,
) {
  const start = afterIndex === null ? 0 : afterIndex + (afterInclusive ? 0 : 1);
  const end =
    beforeIndex === null
      ? rows.length
      : beforeIndex + (beforeInclusive ? 1 : 0);
  const bounded = rows.slice(start, Math.min(end, start + limit));
  return {
    rows: bounded,
    hasNextPage: start + bounded.length < end,
  };
}

function reversePage(
  rows: Array<{ id: string; order: number; title: string }>,
  afterIndex: number | null,
  limit: number,
) {
  const end = afterIndex === null ? rows.length : afterIndex;
  const reversed = rows.slice(0, end).reverse().slice(0, limit);
  return {
    rows: reversed,
    hasNextPage: reversed.length < end,
  };
}

function cursorFor(row: { id: string; order: number } | undefined) {
  if (!row) return undefined;
  return ["projects", row.order, row.id, row.order];
}

function cursorIndex(cursor: unknown): number | null {
  if (!Array.isArray(cursor)) return null;
  const index = Number(cursor[1]);
  return Number.isInteger(index) ? index : null;
}
