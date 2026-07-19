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

import { stroopwafelV3AppContract } from "./stroopwafel-v3-app-contract.js";
import {
  projectCanonicalStroopwafelGame,
  projectCanonicalStroopwafelRoom,
  publicStroopwafelV3UserEvidence,
} from "./stroopwafel-v3-live-support.js";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const schemaPath = requiredEnvironment("INSTANT_SWIFT_DATA_STROOPWAFEL_SCHEMA_PATH");
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
let db: any;

try {
  const suffix = randomUUID();
  const admin = initAdmin({ appId, adminToken, apiURI });
  const swiftToken = await admin.auth.createToken({
    email: `stroopwafel-swift-${suffix}@example.com`,
  });
  const typeScriptToken = await admin.auth.createToken({
    email: `stroopwafel-typescript-${suffix}@example.com`,
  });
  const swiftUser = await admin.auth.verifyToken(swiftToken);
  const typeScriptUser = await admin.auth.verifyToken(typeScriptToken);
  assert.ok(swiftUser?.id, "Expected a canonical Swift Stroopwafel user.");
  assert.ok(typeScriptUser?.id, "Expected a canonical TypeScript Stroopwafel user.");

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
  await db.transact(
    db.tx.$users[typeScriptUser.id].update({
      handle: "TypeScriptGuest",
      highScore: 0,
      created_at: "2026-07-19T00:00:00.000Z",
    }),
  );

  swift = spawnSwift(swiftToken, swiftUser.id, typeScriptUser.id);
  const lines = createInterface({ input: swift.stdout, crlfDelay: Infinity })
    [Symbol.asyncIterator]();

  const roomReady = await nextJSONLine(lines, swift, "Swift Stroopwafel room readiness");
  assert.equal(roomReady.event, "swift-room-ready", JSON.stringify(roomReady));
  assert.equal(roomReady.ok, true);

  const swiftRoom = await waitForRoom((room) => (
    room.hostId === swiftUser.id
    && room.users.some((user) => user.id === swiftUser.id)
  ));
  await db.transact([
    db.tx.rooms[swiftRoom.id].link({ users: typeScriptUser.id }),
    db.tx.rooms[swiftRoom.id].update({ readyIds: [typeScriptUser.id] }),
  ]);
  const roomAfterTypeScriptReady = await waitForRoom((room) => (
    room.readyIds.includes(typeScriptUser.id)
    && room.users.some((user) => user.id === typeScriptUser.id)
  ));

  const readyObserved = await nextJSONLine(
    lines,
    swift,
    "Swift observation of TypeScript Stroopwafel readiness",
  );
  assert.equal(readyObserved.event, "typescript-ready-observed", JSON.stringify(readyObserved));
  assert.equal(readyObserved.ok, true);

  const gameStarted = await nextJSONLine(lines, swift, "Swift Stroopwafel game start");
  assert.equal(gameStarted.event, "swift-game-started", JSON.stringify(gameStarted));
  assert.equal(gameStarted.ok, true);
  const game = await waitForGame((value) => (
    value.status === stroopwafelV3AppContract.game.inProgress
    && value.playerIds.includes(swiftUser.id)
    && value.playerIds.includes(typeScriptUser.id)
    && value.colors.length === stroopwafelV3AppContract.game.promptCount
    && value.points.length === 2
  ));
  const guestPoint = game.points.find((point) => point.userId === typeScriptUser.id);
  assert.ok(guestPoint, "Expected the TypeScript-owned canonical point.");
  await db.transact(db.tx.points[guestPoint.id].update({ val: 1 }));

  const pointObserved = await nextJSONLine(
    lines,
    swift,
    "Swift observation of TypeScript Stroopwafel point",
  );
  assert.equal(pointObserved.event, "typescript-point-observed", JSON.stringify(pointObserved));
  assert.equal(pointObserved.ok, true);

  const completed = await nextJSONLine(lines, swift, "Swift Stroopwafel completion");
  assert.equal(completed.event, "swift-completion-observed", JSON.stringify(completed));
  assert.equal(completed.ok, true);
  const completedGame = await waitForGame((value) => (
    value.status === stroopwafelV3AppContract.game.completed
    && value.points.some((point) => (
      point.userId === swiftUser.id
      && point.val === stroopwafelV3AppContract.game.scoreToWin
    ))
    && value.points.some((point) => point.userId === typeScriptUser.id && point.val === 1)
    && value.rooms.every((room) => room.currentGameId === undefined)
  ));

  const swiftEvidence = await nextJSONLine(lines, swift, "Swift Stroopwafel evidence");
  await requireSuccessfulExit(swift, "Swift Stroopwafel runner");
  swift = undefined;
  assert.equal(swiftEvidence.ok, true);
  assert.equal(swiftEvidence.event, "typescript-point-and-swift-completion-observed");
  assert.equal(swiftEvidence.details.winningPointValue, 13);
  assert.equal(swiftEvidence.details.typeScriptPointObservedBySwift.value, 1);
  assert.equal(swiftEvidence.details.currentGameIDAfterCompletion, undefined);
  assert.equal(swiftEvidence.details.connectionState, "authenticated");
  assert.deepEqual(warnings, []);

  const output = {
    case: "validation.typescript.stroopwafel-v3-live-contract",
    event: "bidirectional-durable-game-observed",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      upstream: stroopwafelV3AppContract.upstream,
      users: {
        swift: publicStroopwafelV3UserEvidence(swiftUser),
        typeScript: publicStroopwafelV3UserEvidence(typeScriptUser),
      },
      typeScriptObservedSwiftRoom: swiftRoom,
      roomAfterTypeScriptReady,
      typeScriptObservedSwiftGame: game,
      typeScriptObservedCompletedGame: completedGame,
      swift: swiftEvidence.details,
      compilerWarningCount: warnings.length,
      warnings,
    },
  };
  assert.equal(JSON.stringify(output).includes("refresh_token"), false);
  await writeStdout(`${JSON.stringify(output, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
  if (db) db.shutdown();
  if (swift && swift.exitCode === null) swift.kill();
}
process.exit(0);

async function waitForRoom(
  predicate: (room: ReturnType<typeof projectCanonicalStroopwafelRoom>) => boolean,
): Promise<ReturnType<typeof projectCanonicalStroopwafelRoom>> {
  let last: unknown;
  for (let attempt = 0; attempt < 300; attempt += 1) {
    const result = await db.queryOnce({
      rooms: {
        $: { where: { id: stroopwafelV3AppContract.fixtures.room.id } },
        users: {},
      },
    });
    last = result.data;
    const rawRoom = result.data.rooms?.[0];
    if (rawRoom) {
      const room = projectCanonicalStroopwafelRoom(rawRoom);
      if (predicate(room)) return room;
    }
    await delay();
  }
  throw new Error(`Timed out waiting for canonical Stroopwafel room: ${JSON.stringify(last)}`);
}

async function waitForGame(
  predicate: (game: ReturnType<typeof projectCanonicalStroopwafelGame>) => boolean,
): Promise<ReturnType<typeof projectCanonicalStroopwafelGame>> {
  let last: unknown;
  for (let attempt = 0; attempt < 300; attempt += 1) {
    const result = await db.queryOnce({
      games: {
        $: { where: { id: stroopwafelV3AppContract.fixtures.game.id } },
        users: {},
        rooms: { users: {} },
        points: {},
      },
    });
    last = result.data;
    const rawGame = result.data.games?.[0];
    if (rawGame) {
      const game = projectCanonicalStroopwafelGame(rawGame);
      if (predicate(game)) return game;
    }
    await delay();
  }
  throw new Error(`Timed out waiting for canonical Stroopwafel game: ${JSON.stringify(last)}`);
}

function spawnSwift(
  refreshToken: string,
  hostUserID: string,
  guestUserID: string,
): SwiftProcess {
  return spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-stroopwafel-v3",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: appId,
        INSTANT_API_URI: apiURI,
        INSTANT_WEBSOCKET_URI: websocketURI,
        INSTANT_SWIFT_DATA_STROOPWAFEL_REFRESH_TOKEN: refreshToken,
        INSTANT_SWIFT_DATA_STROOPWAFEL_HOST_USER_ID: hostUserID,
        INSTANT_SWIFT_DATA_STROOPWAFEL_GUEST_USER_ID: guestUserID,
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
  throw new Error("Generated Stroopwafel schema did not load.");
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

async function withTimeout<T>(promise: Promise<T>, operation: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error(`Timed out: ${operation}.`)), 45_000);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function delay(): Promise<void> {
  await new Promise((resolveDelay) => setTimeout(resolveDelay, 100));
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
