import assert from "node:assert/strict";
import { spawn, type ChildProcessByStdio } from "node:child_process";
import { randomUUID } from "node:crypto";
import { dirname, resolve } from "node:path";
import { createInterface } from "node:readline";
import type { Readable } from "node:stream";
import { fileURLToPath, pathToFileURL } from "node:url";
import { init as initAdmin } from "@instantdb/admin";
import WebSocket from "ws";
import {
  init as initCore,
  StoreInterface,
  type StoreInterfaceStoreName,
} from "@instantdb/core";

import { todosV3AppContract } from "./todos-v3-app-contract.js";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const schemaPath = requiredEnvironment("INSTANT_SWIFT_DATA_TODOS_SCHEMA_PATH");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI
  ?? "wss://api.instantdb.com/runtime/session";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const swiftTodo: TodoShape = {
  ...todosV3AppContract.swiftCreated,
  id: randomUUID(),
};
const typeScriptTodo: TodoShape = {
  ...todosV3AppContract.typeScriptCreated,
  id: randomUUID(),
};
const offlineTodo: TodoShape = {
  id: randomUUID(),
  text: "Swift offline todo",
  isCompleted: false,
  createdAtMilliseconds: 1_700_000_002_000,
};
const warnings: string[] = [];
const originalWarn = console.warn;
console.warn = (...values) => warnings.push(values.map(String).join(" "));

class MemoryStore extends StoreInterface {
  private readonly values = new Map<string, unknown>();

  constructor(appID: string, storeName: StoreInterfaceStoreName) {
    super(appID, storeName);
  }

  async getItem(key: string): Promise<unknown> {
    return this.values.get(key) ?? null;
  }

  async removeItem(key: string): Promise<void> {
    this.values.delete(key);
  }

  async multiSet(entries: Array<[string, unknown]>): Promise<void> {
    for (const [key, value] of entries) this.values.set(key, value);
  }

  async getAllKeys(): Promise<string[]> {
    return [...this.values.keys()];
  }
}

class AlwaysOnline {
  static async getIsOnline(): Promise<boolean> {
    return true;
  }

  static listen(_listener: (isOnline: boolean) => void): () => void {
    return () => {};
  }
}

try {
  const admin = initAdmin({ appId, adminToken, apiURI });
  const refreshToken = await admin.auth.createToken({
    email: `todos-v3-${appId}@example.com`,
  });
  const user = await admin.auth.verifyToken(refreshToken);
  assert.ok(user?.id, "Expected a canonical Todos V3 user.");

  const schemaModule = await import(pathToFileURL(schemaPath).href);
  const schema = unwrapSchema(schemaModule);
  (globalThis as any).window = globalThis;
  (globalThis as any).BroadcastChannel = undefined;
  (globalThis as any).WebSocket = WebSocket;
  const db = initCore(
    {
      appId,
      apiURI,
      websocketURI,
      schema,
      devtool: false,
      useDateObjects: true,
    },
    MemoryStore,
    AlwaysOnline,
  );
  await db.auth.signInWithToken(refreshToken);
  const room: any = db.joinRoom(todosV3AppContract.roomType, "main");
  room.publishPresence({});

  const swift = await runSwiftWrite({
    appId,
    apiURI,
    websocketURI,
    refreshToken,
    userID: user.id,
    todo: swiftTodo,
    offlineTodo,
  });
  assert.equal(swift.ok, true);
  assert.equal(swift.event, "viewer-and-offline-replay-observed");
  const { performance, ...swiftDetails } = swift.details;
  assert.deepEqual(swiftDetails, {
    roomType: todosV3AppContract.roomType,
    roomID: "main",
    peerCount: 1,
    pendingWhileOffline: 1,
    online: {
      direction: "swift-to-typescript",
      ...swiftTodo,
      connectionState: "authenticated",
      pendingMutationCount: 0,
    },
    offline: {
      direction: "swift-offline-to-typescript",
      ...offlineTodo,
      connectionState: "authenticated",
      pendingMutationCount: 0,
    },
  });
  assert.deepEqual(Object.keys(performance).sort(), [
    "acceptedMutations",
    "authenticateAndConnect",
    "offlineEnqueue",
    "reconnectDrain",
  ]);
  for (const measurement of Object.values(performance) as any[]) {
    assert.ok(measurement.durationNanoseconds > 0);
    assert.ok(measurement.actorHopCount > 0);
    assert.equal(
      measurement.actorHopCount,
      Object.values(measurement.actorHopBreakdown as Record<string, number>)
        .reduce((sum, count) => sum + count, 0),
    );
  }

  const observedByTypeScript = await waitForTodo(
    db,
    swiftTodo,
  );
  assert.deepEqual(observedByTypeScript, swiftTodo);
  const observedOfflineByTypeScript = await waitForTodo(db, offlineTodo);
  assert.deepEqual(observedOfflineByTypeScript, offlineTodo);

  const observer = spawnSwift("--live-todos-v3-observe", {
    appId,
    apiURI,
    websocketURI,
    refreshToken,
    userID: user.id,
    todo: typeScriptTodo,
  });
  const lines = createInterface({ input: observer.stdout, crlfDelay: Infinity })
    [Symbol.asyncIterator]();
  const ready = await nextJSONLine(lines, observer, "Swift Todos observer readiness");
  assert.equal(ready.event, "observer-ready");
  assert.equal(ready.details.direction, "typescript-to-swift");
  assert.equal(ready.details.connectionState, "authenticated");

  const tsTodo = typeScriptTodo;
  await db.transact(
    db.tx.todos[tsTodo.id].update({
      text: tsTodo.text,
      isCompleted: tsTodo.isCompleted,
      createdAt: new Date(tsTodo.createdAtMilliseconds),
    }),
  );

  const observedBySwift = await nextJSONLine(
    lines,
    observer,
    "Swift observation of TypeScript Todo",
  );
  assert.equal(observedBySwift.event, "typescript-todo-observed");
  assert.deepEqual(observedBySwift.details, {
    direction: "typescript-to-swift",
    ...tsTodo,
    connectionState: "authenticated",
    pendingMutationCount: 0,
  });
  await requireSuccessfulExit(observer, "Swift Todos observer");

  assert.deepEqual(warnings, []);
  process.stdout.write(`${JSON.stringify({
    case: "validation.typescript.todos-v3-live-contract",
    event: "bidirectional-todos-observed",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      user: { id: user.id, email: user.email },
      swift: swift.details.online,
      performance,
      room: {
        roomType: swift.details.roomType,
        roomID: swift.details.roomID,
        peerCount: swift.details.peerCount,
      },
      offline: {
        pendingWhileOffline: swift.details.pendingWhileOffline,
        swift: swift.details.offline,
        typeScriptObserved: observedOfflineByTypeScript,
      },
      typeScriptObserved: observedByTypeScript,
      typeScriptCreated: tsTodo,
      swiftObserved: observedBySwift.details,
      compilerWarningCount: warnings.length,
      warnings,
    },
  }, null, 2)}\n`);
  room.leaveRoom();
  db.shutdown();
} finally {
  console.warn = originalWarn;
}

async function runSwiftWrite(input: SwiftInput): Promise<any> {
  const child = spawnSwift("--live-todos-v3-write", input);
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const exitCode = await childExit(child);
  if (exitCode !== 0) {
    throw new Error(
      `Swift Todos writer failed with status ${exitCode}: ${stdout.trim()} ${stderr.trim()}`,
    );
  }
  const lines = stdout.trim().split("\n").filter(Boolean);
  assert.equal(lines.length, 1, "Expected one Swift Todos writer evidence row.");
  return JSON.parse(lines[0]);
}

interface TodoShape {
  id: string;
  text: string;
  isCompleted: boolean;
  createdAtMilliseconds: number;
}

interface SwiftInput {
  appId: string;
  apiURI: string;
  websocketURI: string;
  refreshToken: string;
  userID: string;
  todo: TodoShape;
  offlineTodo?: TodoShape;
}

function spawnSwift(mode: string, input: SwiftInput): SwiftProcess {
  return spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      mode,
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: input.appId,
        INSTANT_API_URI: input.apiURI,
        INSTANT_WEBSOCKET_URI: input.websocketURI,
        INSTANT_SWIFT_DATA_TODOS_V3_REFRESH_TOKEN: input.refreshToken,
        INSTANT_SWIFT_DATA_TODOS_V3_USER_ID: input.userID,
        INSTANT_SWIFT_DATA_TODOS_V3_ID: input.todo.id,
        INSTANT_SWIFT_DATA_TODOS_V3_TEXT: input.todo.text,
        INSTANT_SWIFT_DATA_TODOS_V3_CREATED_AT_MILLISECONDS:
          String(input.todo.createdAtMilliseconds),
        INSTANT_SWIFT_DATA_TODOS_V3_OFFLINE_ID: input.offlineTodo?.id ?? "",
        INSTANT_SWIFT_DATA_TODOS_V3_OFFLINE_TEXT: input.offlineTodo?.text ?? "",
        INSTANT_SWIFT_DATA_TODOS_V3_OFFLINE_CREATED_AT_MILLISECONDS:
          input.offlineTodo ? String(input.offlineTodo.createdAtMilliseconds) : "",
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
}

async function nextJSONLine(
  lines: AsyncIterator<string>,
  child: SwiftProcess,
  operation: string,
): Promise<any> {
  const result = await withTimeout(lines.next(), operation);
  if (result.done) {
    throw new Error(`${operation} ended before producing evidence.`);
  }
  try {
    return JSON.parse(result.value);
  } catch (error) {
    child.kill();
    throw new Error(`${operation} emitted invalid JSON: ${result.value}; ${String(error)}`);
  }
}

async function requireSuccessfulExit(
  child: SwiftProcess,
  operation: string,
): Promise<void> {
  let stderr = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const exitCode = await withTimeout(childExit(child), `${operation} exit`);
  if (exitCode !== 0) {
    throw new Error(`${operation} failed with status ${exitCode}: ${stderr.trim()}`);
  }
}

async function waitForTodo(
  db: any,
  expected: TodoShape,
): Promise<TodoShape> {
  let last: unknown;
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const result = await db.queryOnce({
      todos: { $: { where: { id: expected.id } } },
    });
    last = result.data;
    const todo = result.data.todos?.[0];
    if (
      todo?.id === expected.id
      && todo?.text === expected.text
      && todo?.isCompleted === expected.isCompleted
      && todo?.createdAt instanceof Date
      && todo.createdAt.getTime() === expected.createdAtMilliseconds
    ) {
      return {
        id: todo.id,
        text: todo.text,
        isCompleted: todo.isCompleted,
        createdAtMilliseconds: todo.createdAt.getTime(),
      };
    }
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 100));
  }
  throw new Error(`Timed out waiting for canonical Todos query: ${JSON.stringify(last)}`);
}

function unwrapSchema(module: unknown): any {
  let candidate = module;
  for (let depth = 0; depth < 4; depth += 1) {
    if (candidate && typeof candidate === "object" && "entities" in candidate) {
      return candidate;
    }
    if (!candidate || typeof candidate !== "object" || !("default" in candidate)) break;
    candidate = (candidate as { default: unknown }).default;
  }
  throw new Error("Generated Todos schema did not load as an Instant schema.");
}

function childExit(child: SwiftProcess): Promise<number> {
  if (child.exitCode !== null) return Promise.resolve(child.exitCode);
  return new Promise((resolveCode, reject) => {
    child.once("error", reject);
    child.once("close", (code) => resolveCode(code ?? 1));
  });
}

async function withTimeout<Value>(promise: Promise<Value>, operation: string): Promise<Value> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<Value>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error(`Timed out: ${operation}.`)), 30_000);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}

// The canonical core package retains Node timers after shutdown in Node.
process.exit(0);
