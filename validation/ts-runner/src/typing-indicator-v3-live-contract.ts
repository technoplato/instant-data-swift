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

import { typingIndicatorV3AppContract } from "./typing-indicator-v3-app-contract.js";
import {
  exactTypingIndicatorFrames,
  phaseForTypingIndicatorPresence,
  serverObservedTypingIndicatorFrames,
  type TypingIndicatorPhase as Phase,
  type TypingIndicatorPresence as Presence,
  type TypingIndicatorPresenceFrame as Frame,
} from "./typing-indicator-v3-live-support.js";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const schemaPath = requiredEnvironment("INSTANT_SWIFT_DATA_TYPING_INDICATOR_SCHEMA_PATH");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI
  ?? "wss://api.instantdb.com/runtime/session";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const suffix = randomUUID();
const roomID = typingIndicatorV3AppContract.room.id;
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
    email: `typing-swift-${suffix}@example.com`,
  });
  const typeScriptToken = await admin.auth.createToken({
    email: `typing-typescript-${suffix}@example.com`,
  });
  const swiftUser = await admin.auth.verifyToken(swiftToken);
  const typeScriptUser = await admin.auth.verifyToken(typeScriptToken);
  assert.ok(swiftUser?.id, "Expected a canonical Swift typing user.");
  assert.ok(typeScriptUser?.id, "Expected a canonical TypeScript typing user.");

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
  const room: any = db.joinRoom(typingIndicatorV3AppContract.room.type, roomID);
  let roomClosed = false;

  const publishedSwiftFrames = exactTypingIndicatorFrames("swift-peer");
  const expectedSwiftFrames = serverObservedTypingIndicatorFrames("swift-peer");
  const observedSwiftFrames = new Map<Phase, Frame>();
  const phaseSignals = {
    initial: deferred<Frame>(),
    active: deferred<Frame>(),
    inactive: deferred<Frame>(),
    cleared: deferred<Frame>(),
  };
  let sawInactive = false;
  const unsubscribe = room.subscribePresence({}, (snapshot: any) => {
    const peer = Object.values(snapshot.peers ?? {}).find(
      (value: any) => value?.id === "swift-peer",
    ) as Presence | undefined;
    if (!peer) return;
    const phase = phaseForTypingIndicatorPresence(peer, { sawInactive });
    if (observedSwiftFrames.has(phase)) return;
    if (phase === "inactive") sawInactive = true;
    const expected = expectedSwiftFrames.find((frame) => frame.phase === phase)!;
    assert.deepEqual(peer, expected.presence);
    const observed = { phase, presence: peer };
    observedSwiftFrames.set(phase, observed);
    phaseSignals[phase].resolve(observed);
  });

  const swift = spawnSwift({
    appId,
    apiURI,
    websocketURI,
    refreshToken: swiftToken,
    swiftUserID: swiftUser.id,
    typeScriptUserID: typeScriptUser.id,
    roomID,
  });
  const lines = createInterface({ input: swift.stdout, crlfDelay: Infinity })
    [Symbol.asyncIterator]();

  try {
    await withTimeout(phaseSignals.initial.promise, "observe Swift initial presence");
    room.publishPresence(typingIndicatorV3AppContract.frames.initialPresence);

    await withTimeout(phaseSignals.active.promise, "observe Swift active presence");
    room.publishPresence(typingIndicatorV3AppContract.frames.activePatch);

    await withTimeout(phaseSignals.inactive.promise, "observe Swift inactive presence");
    room.publishPresence(typingIndicatorV3AppContract.frames.inactivePatch);

    await withTimeout(phaseSignals.cleared.promise, "observe Swift cleared presence");
    room.publishPresence(typingIndicatorV3AppContract.frames.timeoutPatch);

    const handshake = await nextJSONLine(lines, swift, "Swift typing frame handshake");
    assert.equal(handshake.event, "typescript-frames-observed");
    assert.equal(handshake.ok, true);

    room.leaveRoom();
    db.shutdown();
    roomClosed = true;

    const swiftEvidence = await nextJSONLine(lines, swift, "Swift typing evidence");
    await requireSuccessfulExit(swift, "Swift typing runner");
    assert.equal(swiftEvidence.ok, true);
    assert.equal(swiftEvidence.event, "bidirectional-presence-frames-observed");
    assert.deepEqual(swiftEvidence.details.publishedFrames, publishedSwiftFrames);
    assert.deepEqual(
      swiftEvidence.details.observedFrames,
      serverObservedTypingIndicatorFrames("typescript-peer"),
    );
    assert.deepEqual(swiftEvidence.details.activePeerIDs, ["typescript-peer"]);
    assert.equal(swiftEvidence.details.peerCountAfterDisconnect, 0);
    assert.deepEqual(
      swiftEvidence.details.serverNormalizations,
      ["chat-input:null-to-absent"],
    );
    assert.equal(swiftEvidence.details.connectionState, "authenticated");
    assert.deepEqual(warnings, []);

    process.stdout.write(`${JSON.stringify({
      case: "validation.typescript.typing-indicator-v3-live-contract",
      event: "bidirectional-presence-frames-observed",
      side: "typescript",
      appID: appId,
      ok: true,
      details: {
        upstream: typingIndicatorV3AppContract.upstream,
        users: {
          swift: { id: swiftUser.id, email: swiftUser.email },
          typeScript: { id: typeScriptUser.id, email: typeScriptUser.email },
        },
        room: typingIndicatorV3AppContract.room,
        swift: swiftEvidence.details,
        typeScriptPublishedFrames: exactTypingIndicatorFrames("typescript-peer"),
        typeScriptObservedSwiftFrames: expectedSwiftFrames,
        serverNormalizations: ["chat-input:null-to-absent"],
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
  typeScriptUserID: string;
  roomID: string;
}): SwiftProcess {
  return spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-typing-indicator-v3",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: input.appId,
        INSTANT_API_URI: input.apiURI,
        INSTANT_WEBSOCKET_URI: input.websocketURI,
        INSTANT_SWIFT_DATA_TYPING_INDICATOR_REFRESH_TOKEN: input.refreshToken,
        INSTANT_SWIFT_DATA_TYPING_INDICATOR_SWIFT_USER_ID: input.swiftUserID,
        INSTANT_SWIFT_DATA_TYPING_INDICATOR_TYPESCRIPT_USER_ID: input.typeScriptUserID,
        INSTANT_SWIFT_DATA_TYPING_INDICATOR_ROOM_ID: input.roomID,
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
  throw new Error("Generated Typing Indicator schema did not load as an Instant schema.");
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

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}
