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

import {
  mergeTileGameBoardPatch,
  mergeTileGameEmptyState,
  mergeTileGameMergedState,
  mergeTileGamePresence,
  mergeTileGameV3AppContract,
} from "./merge-tile-game-v3-app-contract.js";
import {
  projectCanonicalMergeTileBoard,
  projectCanonicalMergeTilePeer,
  publicMergeTileGameUserEvidence,
} from "./merge-tile-game-v3-live-support.js";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const schemaPath = requiredEnvironment("INSTANT_SWIFT_DATA_MERGE_TILE_GAME_SCHEMA_PATH");
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
let unsubscribePresence: (() => void) | undefined;
let room: any;
let db: any;

try {
  const suffix = randomUUID();
  const admin = initAdmin({ appId, adminToken, apiURI });
  const swiftToken = await admin.auth.createToken({
    email: `merge-tile-swift-${suffix}@example.com`,
  });
  const typeScriptToken = await admin.auth.createToken({
    email: `merge-tile-typescript-${suffix}@example.com`,
  });
  const swiftUser = await admin.auth.verifyToken(swiftToken);
  const typeScriptUser = await admin.auth.verifyToken(typeScriptToken);
  assert.ok(swiftUser?.id, "Expected a canonical Swift Merge Tile Game user.");
  assert.ok(typeScriptUser?.id, "Expected a canonical TypeScript Merge Tile Game user.");

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
  room = db.joinRoom(
    mergeTileGameV3AppContract.room.type,
    mergeTileGameV3AppContract.room.id,
  );

  const roomReady = deferred<void>();
  const observedSwiftPeer = deferred<ReturnType<typeof projectCanonicalMergeTilePeer>>();
  unsubscribePresence = room.subscribePresence({}, (snapshot: any) => {
    roomReady.resolve();
    for (const rawPeer of Object.values(snapshot.peers ?? {}) as unknown[]) {
      let peer: ReturnType<typeof projectCanonicalMergeTilePeer>;
      try {
        peer = projectCanonicalMergeTilePeer(rawPeer);
      } catch {
        continue;
      }
      if (peer.color === mergeTileGameV3AppContract.fixtures.swift.color) {
        observedSwiftPeer.resolve(peer);
      }
    }
  });
  await withTimeout(roomReady.promise, "join TypeScript Merge Tile Game room");

  swift = spawnSwift(swiftToken, swiftUser.id);
  const lines = createInterface({ input: swift.stdout, crlfDelay: Infinity })
    [Symbol.asyncIterator]();

  const swiftReady = await nextJSONLine(lines, swift, "Swift Merge Tile Game readiness");
  assert.equal(swiftReady.event, "swift-merge-and-presence-ready");
  assert.equal(swiftReady.ok, true);

  const swiftPeer = await withTimeout(
    observedSwiftPeer.promise,
    "observe exact Swift Merge Tile Game presence",
  );
  assert.equal(swiftPeer.color, mergeTileGameV3AppContract.fixtures.swift.color);

  const swiftBoard = await waitForBoard((state) => (
    state[mergeTileGameV3AppContract.fixtures.swift.cell]
      === mergeTileGameV3AppContract.fixtures.swift.color
  ));

  const typeScriptFixture = mergeTileGameV3AppContract.fixtures.typeScript;
  const typeScriptPatch = mergeTileGameBoardPatch(
    typeScriptFixture.cell,
    typeScriptFixture.color,
  );
  await db.transact([
    db.tx.boards[mergeTileGameV3AppContract.board.id].merge(typeScriptPatch),
  ]);
  const typeScriptPresence = mergeTileGamePresence(typeScriptFixture.color);
  room.publishPresence(typeScriptPresence);

  const mergeHandshake = await nextJSONLine(
    lines,
    swift,
    "Swift TypeScript independent merge observation",
  );
  assert.equal(mergeHandshake.event, "typescript-independent-merge-observed");
  assert.equal(mergeHandshake.ok, true);

  const expectedMergedState = mergeTileGameMergedState(
    swiftBoard.state,
    typeScriptPatch,
  );
  const boardAfterBothMerges = await waitForBoard((state) => (
    state[mergeTileGameV3AppContract.fixtures.swift.cell]
      === mergeTileGameV3AppContract.fixtures.swift.color
    && state[typeScriptFixture.cell] === typeScriptFixture.color
  ));
  assert.deepEqual(boardAfterBothMerges.state, expectedMergedState);

  const emptyState = mergeTileGameEmptyState();
  await db.transact([
    db.tx.boards[mergeTileGameV3AppContract.board.id].update({ state: emptyState }),
  ]);
  const resetHandshake = await nextJSONLine(lines, swift, "Swift reset observation");
  assert.equal(resetHandshake.event, "typescript-reset-observed");
  assert.equal(resetHandshake.ok, true);
  const boardAfterReset = await waitForBoard((state) => deepEqual(state, emptyState));

  unsubscribePresence?.();
  unsubscribePresence = undefined;
  room.leaveRoom();
  db.shutdown();
  room = undefined;
  db = undefined;

  const swiftEvidence = await nextJSONLine(lines, swift, "Swift Merge Tile Game evidence");
  await requireSuccessfulExit(swift, "Swift Merge Tile Game runner");
  swift = undefined;
  assert.equal(swiftEvidence.ok, true);
  assert.equal(swiftEvidence.event, "independent-merges-reset-and-disconnect-observed");
  assert.deepEqual(swiftEvidence.details.boardStateAfterBothMerges, expectedMergedState);
  assert.deepEqual(swiftEvidence.details.boardStateAfterReset, emptyState);
  assert.equal(swiftEvidence.details.remoteColorPeerCount, 1);
  assert.equal(swiftEvidence.details.remotePeerCountAfterDisconnect, 0);
  assert.equal(swiftEvidence.details.connectionState, "authenticated");
  assert.deepEqual(warnings, []);

  const output = {
    case: "validation.typescript.merge-tile-game-v3-live-contract",
    event: "independent-merges-reset-and-disconnect-observed",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      upstream: mergeTileGameV3AppContract.upstream,
      users: {
        swift: publicMergeTileGameUserEvidence(swiftUser),
        typeScript: publicMergeTileGameUserEvidence(typeScriptUser),
      },
      board: mergeTileGameV3AppContract.board,
      room: mergeTileGameV3AppContract.room,
      typeScriptObservedSwiftBoard: swiftBoard,
      typeScriptObservedSwiftPeer: swiftPeer,
      typeScriptPublishedPatch: typeScriptPatch,
      typeScriptPublishedPresence: typeScriptPresence,
      boardAfterBothMerges,
      boardAfterReset,
      swift: swiftEvidence.details,
      compilerWarningCount: warnings.length,
      warnings,
    },
  };
  assert.equal(JSON.stringify(output).includes("refresh_token"), false);
  await writeStdout(`${JSON.stringify(output, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
  if (unsubscribePresence) unsubscribePresence();
  if (room) room.leaveRoom();
  if (db) db.shutdown();
  if (swift && swift.exitCode === null) swift.kill();
}
process.exit(0);

async function waitForBoard(
  predicate: (state: Record<string, string>) => boolean,
): Promise<ReturnType<typeof projectCanonicalMergeTileBoard>> {
  let last: unknown;
  for (let attempt = 0; attempt < 200; attempt += 1) {
    const result = await db.queryOnce({
      boards: { $: { where: { id: mergeTileGameV3AppContract.board.id } } },
    });
    last = result.data;
    const rawBoard = result.data.boards?.[0];
    if (rawBoard) {
      const board = projectCanonicalMergeTileBoard(rawBoard);
      if (predicate(board.state)) return board;
    }
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 100));
  }
  throw new Error(`Timed out waiting for canonical Merge Tile Game board: ${JSON.stringify(last)}`);
}

function spawnSwift(refreshToken: string, userID: string): SwiftProcess {
  return spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-merge-tile-game-v3",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: appId,
        INSTANT_API_URI: apiURI,
        INSTANT_WEBSOCKET_URI: websocketURI,
        INSTANT_SWIFT_DATA_MERGE_TILE_GAME_REFRESH_TOKEN: refreshToken,
        INSTANT_SWIFT_DATA_MERGE_TILE_GAME_SWIFT_USER_ID: userID,
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
  throw new Error("Generated Merge Tile Game schema did not load.");
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
    throw new Error(`${operation} emitted invalid JSON: ${line.value}; ${String(error)}`);
  }
}

async function requireSuccessfulExit(child: SwiftProcess, operation: string): Promise<void> {
  let stderr = "";
  child.stderr.on("data", (chunk) => { stderr += String(chunk); });
  const code = await withTimeout(new Promise<number>((resolveCode, reject) => {
    if (child.exitCode !== null) return resolveCode(child.exitCode);
    child.once("error", reject);
    child.once("close", (value) => resolveCode(value ?? 1));
  }), `${operation} exit`);
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
