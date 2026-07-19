import assert from "node:assert/strict";
import { spawn, type ChildProcessByStdio } from "node:child_process";
import { randomUUID } from "node:crypto";
import { dirname, resolve } from "node:path";
import { createInterface } from "node:readline";
import type { Readable } from "node:stream";
import { fileURLToPath, pathToFileURL } from "node:url";
import { init as initAdmin } from "@instantdb/admin";
import {
  init as initCore,
  StoreInterface,
  type StoreInterfaceStoreName,
} from "@instantdb/core";

import {
  reactionsV3AppContract,
  type ReactionsV3Payload,
} from "./reactions-v3-app-contract.js";
import { exactReactionPayload } from "./reactions-v3-live-support.js";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const schemaPath = requiredEnvironment("INSTANT_SWIFT_DATA_REACTIONS_SCHEMA_PATH");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI
  ?? "wss://api.instantdb.com/runtime/session";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const suffix = randomUUID();
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
  const swiftToken = await admin.auth.createToken({
    email: `reactions-swift-${suffix}@example.com`,
  });
  const typeScriptToken = await admin.auth.createToken({
    email: `reactions-typescript-${suffix}@example.com`,
  });
  const swiftUser = await admin.auth.verifyToken(swiftToken);
  const typeScriptUser = await admin.auth.verifyToken(typeScriptToken);
  assert.ok(swiftUser?.id, "Expected a canonical Swift reactions user.");
  assert.ok(typeScriptUser?.id, "Expected a canonical TypeScript reactions user.");

  const schemaModule = await import(pathToFileURL(schemaPath).href);
  const schema = unwrapSchema(schemaModule);
  (globalThis as any).window = globalThis;
  (globalThis as any).BroadcastChannel = undefined;

  const db = initCore(
    { appId, apiURI, websocketURI, schema, devtool: false },
    MemoryStore,
    AlwaysOnline,
  );
  await db.auth.signInWithToken(typeScriptToken);
  const room: any = db.joinRoom(
    reactionsV3AppContract.room.type,
    reactionsV3AppContract.room.id,
  );
  let roomClosed = false;
  const observedSwiftPayload = deferred<ReactionsV3Payload>();
  const unsubscribe = room.subscribeTopic(
    reactionsV3AppContract.room.topic,
    (value: unknown) => {
      let payload: ReactionsV3Payload;
      try {
        payload = exactReactionPayload(value);
      } catch {
        return;
      }
      if (matches(payload, reactionsV3AppContract.swiftPublished)) {
        observedSwiftPayload.resolve(payload);
      }
    },
  );

  const swift = spawnSwift({
    appId,
    apiURI,
    websocketURI,
    refreshToken: swiftToken,
    swiftUserID: swiftUser.id,
    roomID: reactionsV3AppContract.room.id,
  });
  const lines = createInterface({ input: swift.stdout, crlfDelay: Infinity })
    [Symbol.asyncIterator]();

  try {
    const swiftPayload = await withTimeout(
      observedSwiftPayload.promise,
      "observe exact Swift reaction",
    );
    assert.deepEqual(swiftPayload, reactionsV3AppContract.swiftPublished);

    room.publishTopic(
      reactionsV3AppContract.room.topic,
      reactionsV3AppContract.typeScriptPublished,
    );
    room.publishTopic(reactionsV3AppContract.room.topic, {
      name: reactionsV3AppContract.invalidReceivedName,
      directionAngle: 135,
      rotationAngle: 315,
    });

    const handshake = await nextJSONLine(lines, swift, "Swift reactions handshake");
    assert.equal(handshake.event, "typescript-payloads-observed");
    assert.equal(handshake.ok, true);

    const swiftEvidence = await nextJSONLine(lines, swift, "Swift reactions evidence");
    await requireSuccessfulExit(swift, "Swift reactions runner");
    assert.equal(swiftEvidence.ok, true);
    assert.equal(swiftEvidence.event, "bidirectional-topic-payloads-observed");
    assert.deepEqual(swiftEvidence.details.publishedPayload, swiftPayload);
    assert.deepEqual(
      swiftEvidence.details.observedPayload,
      reactionsV3AppContract.typeScriptPublished,
    );
    assert.equal(
      swiftEvidence.details.ignoredInvalidName,
      reactionsV3AppContract.invalidReceivedName,
    );
    assert.equal(swiftEvidence.details.connectionState, "authenticated");
    assert.deepEqual(warnings, []);

    room.leaveRoom();
    db.shutdown();
    roomClosed = true;

    process.stdout.write(`${JSON.stringify({
      case: "validation.typescript.reactions-v3-live-contract",
      event: "bidirectional-topic-payloads-observed",
      side: "typescript",
      appID: appId,
      ok: true,
      details: {
        upstream: reactionsV3AppContract.upstream,
        users: {
          swift: { id: swiftUser.id, email: swiftUser.email },
          typeScript: { id: typeScriptUser.id, email: typeScriptUser.email },
        },
        room: reactionsV3AppContract.room,
        swift: swiftEvidence.details,
        typeScriptPublishedPayload: reactionsV3AppContract.typeScriptPublished,
        typeScriptInvalidPayload: {
          name: reactionsV3AppContract.invalidReceivedName,
          directionAngle: 135,
          rotationAngle: 315,
        },
        typeScriptObservedSwiftPayload: swiftPayload,
        compilerWarningCount: warnings.length,
        warnings,
      },
    }, null, 2)}\n`);
  } finally {
    unsubscribe();
    if (!roomClosed) {
      room.leaveRoom();
      db.shutdown();
    }
  }
} finally {
  console.warn = originalWarn;
}

function spawnSwift(input: {
  appId: string;
  apiURI: string;
  websocketURI: string;
  refreshToken: string;
  swiftUserID: string;
  roomID: string;
}): SwiftProcess {
  return spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-reactions-v3",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: input.appId,
        INSTANT_API_URI: input.apiURI,
        INSTANT_WEBSOCKET_URI: input.websocketURI,
        INSTANT_SWIFT_DATA_REACTIONS_REFRESH_TOKEN: input.refreshToken,
        INSTANT_SWIFT_DATA_REACTIONS_SWIFT_USER_ID: input.swiftUserID,
        INSTANT_SWIFT_DATA_REACTIONS_ROOM_ID: input.roomID,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
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
  throw new Error("Generated Reactions schema did not load as an Instant schema.");
}

async function nextJSONLine(
  lines: AsyncIterator<string>,
  child: SwiftProcess,
  operation: string,
): Promise<any> {
  const result = await withTimeout(lines.next(), operation);
  if (result.done) throw new Error(`${operation} ended before producing evidence.`);
  try {
    return JSON.parse(result.value);
  } catch (error) {
    child.kill();
    throw new Error(`${operation} emitted invalid JSON: ${result.value}; ${String(error)}`);
  }
}

async function requireSuccessfulExit(child: SwiftProcess, operation: string): Promise<void> {
  let stderr = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const exitCode = await withTimeout(childExit(child), `${operation} exit`);
  if (exitCode !== 0) {
    throw new Error(`${operation} failed with status ${exitCode}: ${stderr.trim()}`);
  }
}

function childExit(child: SwiftProcess): Promise<number> {
  if (child.exitCode !== null) return Promise.resolve(child.exitCode);
  return new Promise((resolveCode, reject) => {
    child.once("error", reject);
    child.once("close", (code) => resolveCode(code ?? 1));
  });
}

function deferred<Value>(): { promise: Promise<Value>; resolve: (value: Value) => void } {
  let resolveValue!: (value: Value) => void;
  const promise = new Promise<Value>((resolveValuePromise) => {
    resolveValue = resolveValuePromise;
  });
  return { promise, resolve: resolveValue };
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

function matches(actual: unknown, expected: unknown): boolean {
  return JSON.stringify(actual) === JSON.stringify(expected);
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}
