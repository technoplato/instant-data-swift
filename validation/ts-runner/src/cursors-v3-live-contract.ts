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
import WebSocket from "ws";

import { cursorsV3AppContract } from "./cursors-v3-app-contract.js";
import {
  projectCanonicalCursorPeer,
  publicCursorsUserEvidence,
} from "./cursors-v3-live-support.js";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const schemaPath = requiredEnvironment("INSTANT_SWIFT_DATA_CURSORS_SCHEMA_PATH");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI
  ?? "wss://api.instantdb.com/runtime/session";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
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

let swift: SwiftProcess | undefined;
let unsubscribe: (() => void) | undefined;
let room: any;
let db: any;

try {
  const suffix = randomUUID();
  const admin = initAdmin({ appId, adminToken, apiURI });
  const swiftToken = await admin.auth.createToken({
    email: `cursors-swift-${suffix}@example.com`,
  });
  const typeScriptToken = await admin.auth.createToken({
    email: `cursors-typescript-${suffix}@example.com`,
  });
  const swiftUser = await admin.auth.verifyToken(swiftToken);
  const typeScriptUser = await admin.auth.verifyToken(typeScriptToken);
  assert.ok(swiftUser?.id, "Expected a canonical Swift cursors user.");
  assert.ok(typeScriptUser?.id, "Expected a canonical TypeScript cursors user.");

  const schema = unwrapSchema(await import(pathToFileURL(schemaPath).href));
  (globalThis as any).window = globalThis;
  (globalThis as any).BroadcastChannel = undefined;
  (globalThis as any).WebSocket = WebSocket;

  db = initCore(
    { appId, apiURI, websocketURI, schema, devtool: false },
    MemoryStore,
    AlwaysOnline,
  );
  await db.auth.signInWithToken(typeScriptToken);
  room = db.joinRoom(cursorsV3AppContract.room.type, cursorsV3AppContract.room.id);

  const roomReady = deferred<void>();
  const observedSwiftCursor = deferred<ReturnType<typeof projectCanonicalCursorPeer>>();
  unsubscribe = room.subscribePresence({}, (snapshot: any) => {
    roomReady.resolve();
    const rawPeers = Object.values(snapshot.peers ?? {}) as unknown[];
    for (const rawPeer of rawPeers) {
      let peer: ReturnType<typeof projectCanonicalCursorPeer>;
      try {
        peer = projectCanonicalCursorPeer(rawPeer);
      } catch {
        continue;
      }
      if (peer.cursor && deepEqual(peer.cursor, cursorsV3AppContract.fixtures.swift)) {
        observedSwiftCursor.resolve(peer);
      }
    }
  });
  await withTimeout(roomReady.promise, "join TypeScript cursors room");

  swift = spawnSwift(swiftToken, swiftUser.id);
  const lines = createInterface({ input: swift.stdout, crlfDelay: Infinity })
    [Symbol.asyncIterator]();

  const swiftPeer = await withTimeout(
    observedSwiftCursor.promise,
    "observe exact Swift cursor",
  );
  assert.deepEqual(swiftPeer.cursor, cursorsV3AppContract.fixtures.swift);

  room.publishPresence({
    [cursorsV3AppContract.room.spaceID]: cursorsV3AppContract.fixtures.typeScript,
  });
  const observedHandshake = await nextJSONLine(lines, swift, "Swift cursor observation");
  assert.equal(observedHandshake.event, "typescript-cursor-observed");
  assert.equal(observedHandshake.ok, true);

  room.publishPresence({ [cursorsV3AppContract.room.spaceID]: undefined });
  const clearedHandshake = await nextJSONLine(lines, swift, "Swift cursor clear");
  assert.equal(clearedHandshake.event, "typescript-cursor-cleared");
  assert.equal(clearedHandshake.ok, true);

  unsubscribe?.();
  unsubscribe = undefined;
  room.leaveRoom();
  db.shutdown();
  room = undefined;
  db = undefined;

  const swiftEvidence = await nextJSONLine(lines, swift, "Swift cursors evidence");
  await requireSuccessfulExit(swift, "Swift cursors runner");
  swift = undefined;
  assert.equal(swiftEvidence.ok, true);
  assert.equal(swiftEvidence.event, "cursor-publish-clear-disconnect-observed");
  assert.deepEqual(
    swiftEvidence.details.publishedCursor,
    cursorsV3AppContract.fixtures.swift,
  );
  assert.deepEqual(
    swiftEvidence.details.observedCursor,
    cursorsV3AppContract.fixtures.typeScript,
  );
  assert.equal(swiftEvidence.details.remoteCursorCount, 1);
  assert.equal(swiftEvidence.details.remoteCursorCountAfterClear, 0);
  assert.equal(swiftEvidence.details.remotePeerCountAfterDisconnect, 0);
  assert.equal(swiftEvidence.details.connectionState, "authenticated");
  assert.deepEqual(warnings, []);

  const output = {
    case: "validation.typescript.cursors-v3-live-contract",
    event: "cursor-publish-clear-disconnect-observed",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      upstream: cursorsV3AppContract.upstream,
      users: {
        swift: publicCursorsUserEvidence(swiftUser),
        typeScript: publicCursorsUserEvidence(typeScriptUser),
      },
      room: cursorsV3AppContract.room,
      typeScriptObservedSwift: swiftPeer,
      typeScriptPublished: cursorsV3AppContract.fixtures.typeScript,
      typeScriptClearedSpaceID: cursorsV3AppContract.room.spaceID,
      swift: swiftEvidence.details,
      cleanup: {
        remoteCursorCountAfterClear: 0,
        remotePeerCountAfterDisconnect: 0,
      },
      compilerWarningCount: warnings.length,
      warnings,
    },
  };
  assert.equal(JSON.stringify(output).includes("refresh_token"), false);
  await writeStdout(`${JSON.stringify(output, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
  if (unsubscribe) unsubscribe();
  if (room) room.leaveRoom();
  if (db) db.shutdown();
  if (swift && swift.exitCode === null) swift.kill();
}
process.exit(0);

function spawnSwift(refreshToken: string, userID: string): SwiftProcess {
  return spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-cursors-v3",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: appId,
        INSTANT_API_URI: apiURI,
        INSTANT_WEBSOCKET_URI: websocketURI,
        INSTANT_SWIFT_DATA_CURSORS_REFRESH_TOKEN: refreshToken,
        INSTANT_SWIFT_DATA_CURSORS_SWIFT_USER_ID: userID,
        INSTANT_SWIFT_DATA_CURSORS_ROOM_ID: cursorsV3AppContract.room.id,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
}

function unwrapSchema(module: any): any {
  let value = module;
  for (let index = 0; index < 4; index += 1) {
    if (value && typeof value === "object" && "entities" in value) return value;
    value = value?.default;
  }
  throw new Error("Generated Cursors schema did not load.");
}

async function nextJSONLine(
  lines: AsyncIterator<string>,
  child: SwiftProcess,
  operation: string,
): Promise<any> {
  const line = await withTimeout(lines.next(), operation);
  if (line.done) throw new Error(`${operation} ended early.`);
  try {
    return JSON.parse(line.value);
  } catch (error) {
    child.kill();
    throw error;
  }
}

async function requireSuccessfulExit(child: SwiftProcess, operation: string): Promise<void> {
  let stderr = "";
  child.stderr.on("data", (chunk) => { stderr += String(chunk); });
  const code = await withTimeout(new Promise<number>((resolveCode, reject) => {
    if (child.exitCode !== null) return resolveCode(child.exitCode);
    child.once("error", reject);
    child.once("close", (value) => resolveCode(value ?? 1));
  }), operation);
  assert.equal(code, 0, stderr);
}

function deferred<T>(): { promise: Promise<T>; resolve: (value: T) => void } {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((resolvePromise) => { resolve = resolvePromise; });
  return { promise, resolve };
}

async function withTimeout<T>(promise: Promise<T>, operation: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error(`Timed out: ${operation}.`)), 30_000);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

function deepEqual(left: unknown, right: unknown): boolean {
  try {
    assert.deepEqual(left, right);
    return true;
  } catch {
    return false;
  }
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}

async function writeStdout(value: string): Promise<void> {
  await new Promise<void>((resolveOutput, rejectOutput) => {
    process.stdout.write(value, (error) => error ? rejectOutput(error) : resolveOutput());
  });
}
