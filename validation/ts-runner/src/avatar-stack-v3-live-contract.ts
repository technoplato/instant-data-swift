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

import { avatarStackV3AppContract } from "./avatar-stack-v3-app-contract.js";
import { projectCanonicalAvatarPeer } from "./avatar-stack-v3-live-support.js";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;
const appId = required("INSTANT_APP_ID");
const adminToken = required("INSTANT_ADMIN_TOKEN");
const schemaPath = required("INSTANT_SWIFT_DATA_AVATAR_STACK_SCHEMA_PATH");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI ?? "wss://api.instantdb.com/runtime/session";
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const warnings: string[] = [];
const originalWarn = console.warn;
console.warn = (...values) => warnings.push(values.map(String).join(" "));

class MemoryStore extends StoreInterface {
  private values = new Map<string, unknown>();
  constructor(appID: string, storeName: StoreInterfaceStoreName) { super(appID, storeName); }
  async getItem(key: string): Promise<unknown> { return this.values.get(key) ?? null; }
  async removeItem(key: string): Promise<void> { this.values.delete(key); }
  async multiSet(entries: Array<[string, unknown]>): Promise<void> {
    for (const [key, value] of entries) this.values.set(key, value);
  }
  async getAllKeys(): Promise<string[]> { return [...this.values.keys()]; }
}
class AlwaysOnline {
  static async getIsOnline(): Promise<boolean> { return true; }
  static listen(_listener: (online: boolean) => void): () => void { return () => {}; }
}

try {
  const suffix = randomUUID();
  const admin = initAdmin({ appId, adminToken, apiURI });
  const swiftToken = await admin.auth.createToken({ email: `avatar-swift-${suffix}@example.com` });
  const typeScriptToken = await admin.auth.createToken({ email: `avatar-ts-${suffix}@example.com` });
  const swiftUser = await admin.auth.verifyToken(swiftToken);
  const typeScriptUser = await admin.auth.verifyToken(typeScriptToken);
  assert.ok(swiftUser?.id);
  assert.ok(typeScriptUser?.id);

  const schema = unwrapSchema(await import(pathToFileURL(schemaPath).href));
  (globalThis as any).window = globalThis;
  (globalThis as any).BroadcastChannel = undefined;
  (globalThis as any).WebSocket = WebSocket;
  const db = initCore({ appId, apiURI, websocketURI, schema, devtool: false }, MemoryStore, AlwaysOnline);
  await db.auth.signInWithToken(typeScriptToken);
  const room: any = db.joinRoom(avatarStackV3AppContract.room.type, avatarStackV3AppContract.room.id);
  let closed = false;
  let unsubscribed = false;
  let sawSwift = false;
  const ready = deferred<void>();
  const swiftPeer = deferred<ReturnType<typeof projectCanonicalAvatarPeer>>();
  const swiftDisconnected = deferred<void>();
  const unsubscribe = room.subscribePresence({}, (snapshot: any) => {
    ready.resolve();
    const values = Object.values(snapshot.peers ?? {}) as Array<Record<string, unknown>>;
    const raw = values.find((peer) => peer.name === avatarStackV3AppContract.fixtures.swift.presence.name);
    if (raw) {
      sawSwift = true;
      swiftPeer.resolve(projectCanonicalAvatarPeer(raw));
    } else if (sawSwift) {
      swiftDisconnected.resolve();
    }
  });
  await timeout(ready.promise, "join TypeScript avatar room");

  const swift = spawnSwift(swiftToken, swiftUser.id);
  const lines = createInterface({ input: swift.stdout, crlfDelay: Infinity })[Symbol.asyncIterator]();
  const observedSwift = await timeout(swiftPeer.promise, "observe Swift avatar");
  assert.deepEqual(observedSwift.presence, avatarStackV3AppContract.fixtures.swift.presence);
  room.publishPresence(avatarStackV3AppContract.fixtures.typeScript.presence);

  const handshake = await nextJSON(lines, swift, "Swift avatar handshake");
  assert.equal(handshake.event, "typescript-presence-observed");
  unsubscribe();
  unsubscribed = true;
  room.leaveRoom();
  db.shutdown();
  closed = true;

  const swiftEvidence = await nextJSON(lines, swift, "Swift avatar evidence");
  await successfulExit(swift);
  assert.equal(swiftEvidence.ok, true);
  assert.deepEqual(swiftEvidence.details.publishedPresence, avatarStackV3AppContract.fixtures.swift.presence);
  assert.deepEqual(swiftEvidence.details.observedPresence, avatarStackV3AppContract.fixtures.typeScript.presence);
  assert.equal(swiftEvidence.details.peerCountAfterDisconnect, 0);
  assert.deepEqual(warnings, []);

  await new Promise<void>((resolveOutput, rejectOutput) => process.stdout.write(`${JSON.stringify({
    case: "validation.typescript.avatar-stack-v3-live-contract",
    event: "bidirectional-presence-observed",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      upstream: avatarStackV3AppContract.upstream,
      users: { swift: swiftUser, typeScript: typeScriptUser },
      room: avatarStackV3AppContract.room,
      typeScriptObservedSwift: observedSwift,
      typeScriptPublished: avatarStackV3AppContract.fixtures.typeScript.presence,
      swift: swiftEvidence.details,
      disconnectCleanup: { swiftPeerRemoved: true, peerCountAfterDisconnect: 0 },
      compilerWarningCount: warnings.length,
      warnings,
    },
  }, null, 2)}\n`, (error) => error ? rejectOutput(error) : resolveOutput()));

  if (!unsubscribed) unsubscribe();
  if (!closed) { room.leaveRoom(); db.shutdown(); }
  void swiftDisconnected;
} finally {
  console.warn = originalWarn;
}
process.exit(0);

function spawnSwift(refreshToken: string, userID: string): SwiftProcess {
  return spawn("swift", ["run", "--package-path", root, "instant-swift-data-validation-runner", "--live-avatar-stack-v3"], {
    cwd: root,
    env: {
      ...process.env,
      INSTANT_APP_ID: appId,
      INSTANT_API_URI: apiURI,
      INSTANT_WEBSOCKET_URI: websocketURI,
      INSTANT_SWIFT_DATA_AVATAR_STACK_REFRESH_TOKEN: refreshToken,
      INSTANT_SWIFT_DATA_AVATAR_STACK_SWIFT_USER_ID: userID,
      INSTANT_SWIFT_DATA_AVATAR_STACK_ROOM_ID: avatarStackV3AppContract.room.id,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
}
function unwrapSchema(module: any): any {
  let value = module;
  for (let index = 0; index < 4; index += 1) {
    if (value && typeof value === "object" && "entities" in value) return value;
    value = value?.default;
  }
  throw new Error("Generated Avatar Stack schema did not load.");
}
async function nextJSON(lines: AsyncIterator<string>, child: SwiftProcess, operation: string): Promise<any> {
  const line = await timeout(lines.next(), operation);
  if (line.done) throw new Error(`${operation} ended early.`);
  try { return JSON.parse(line.value); } catch (error) { child.kill(); throw error; }
}
async function successfulExit(child: SwiftProcess): Promise<void> {
  let stderr = "";
  child.stderr.on("data", (chunk) => { stderr += String(chunk); });
  const code = await timeout(new Promise<number>((resolveCode, reject) => {
    if (child.exitCode !== null) return resolveCode(child.exitCode);
    child.once("error", reject);
    child.once("close", (value) => resolveCode(value ?? 1));
  }), "Swift avatar runner exit");
  assert.equal(code, 0, stderr);
}
function deferred<T>(): { promise: Promise<T>; resolve: (value: T) => void } {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => { resolve = r; });
  return { promise, resolve };
}
async function timeout<T>(promise: Promise<T>, operation: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([promise, new Promise<T>((_r, reject) => {
      timer = setTimeout(() => reject(new Error(`Timed out: ${operation}.`)), 30_000);
    })]);
  } finally { if (timer) clearTimeout(timer); }
}
function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}
