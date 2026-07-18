import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { dirname, resolve } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { init as initAdmin } from "@instantdb/admin";
import {
  init as initCore,
  StoreInterface,
  type StoreInterfaceStoreName,
} from "@instantdb/core";
import { playbackRoomContract } from "./playback-room-sdk-contract.js";

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const schemaPath = requiredEnvironment("INSTANT_SWIFT_DATA_RECORDING_SCHEMA_PATH");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI
  ?? "wss://api.instantdb.com/runtime/session";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const suffix = randomUUID();
const roomID = `playback-${suffix}`;
const warnings: string[] = [];
const originalWarn = console.warn;
console.warn = (...values) => warnings.push(values.map(String).join(" "));

class MemoryStore extends StoreInterface {
  private readonly values = new Map<string, unknown>();

  constructor(appId: string, storeName: StoreInterfaceStoreName) {
    super(appId, storeName);
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
    email: `playback-swift-${suffix}@example.com`,
  });
  const typeScriptToken = await admin.auth.createToken({
    email: `playback-typescript-${suffix}@example.com`,
  });
  const swiftUser = await admin.auth.verifyToken(swiftToken);
  const typeScriptUser = await admin.auth.verifyToken(typeScriptToken);
  assert.ok(swiftUser?.id, "Expected a canonical Swift room user.");
  assert.ok(typeScriptUser?.id, "Expected a canonical TypeScript room user.");
  const contract = playbackRoomContract({
    swiftUserID: swiftUser.id,
    typeScriptUserID: typeScriptUser.id,
  });
  const swiftPresence = contract.initial.swift.presence;
  const swiftTopics = contract.initial.swift.topics;
  const typeScriptPresence = contract.initial.typeScript.presence;
  const typeScriptTopics = contract.initial.typeScript.topics;
  const reconnectedSwiftPresence = contract.reconnect.swift.presence;
  const reconnectedSwiftTopics = contract.reconnect.swift.topics;
  const reconnectedTypeScriptPresence = contract.reconnect.typeScript.presence;
  const reconnectedTypeScriptTopics = contract.reconnect.typeScript.topics;

  const schemaModule = await import(pathToFileURL(schemaPath).href);
  const schema = unwrapSchema(schemaModule);
  (globalThis as any).window = globalThis;
  (globalThis as any).BroadcastChannel = undefined;
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
  await db.auth.signInWithToken(typeScriptToken);

  const room: any = db.joinRoom("recording.playback", roomID);
  const observedPresence = deferred<typeof swiftPresence>();
  const observedReaction = deferred<typeof swiftTopics.reaction>();
  const observedDraft = deferred<typeof swiftTopics.commentDraft>();
  const observedCommitted = deferred<typeof swiftTopics.commentCommitted>();
  const observedReconnectedPresence = deferred<typeof reconnectedSwiftPresence>();
  const observedReconnectedReaction = deferred<typeof reconnectedSwiftTopics.reaction>();
  const observedReconnectedDraft = deferred<typeof reconnectedSwiftTopics.commentDraft>();
  const observedReconnectedCommitted = deferred<
    typeof reconnectedSwiftTopics.commentCommitted
  >();
  const unsubscribePresence = room.subscribePresence({}, (presence: any) => {
    for (const peer of Object.values(presence.peers ?? {})) {
      if (matches(peer, swiftPresence)) observedPresence.resolve(swiftPresence);
      if (matches(peer, reconnectedSwiftPresence)) {
        observedReconnectedPresence.resolve(reconnectedSwiftPresence);
      }
    }
  });
  const unsubscribeReaction = room.subscribeTopic("reaction", (value: any) => {
    if (matches(value, swiftTopics.reaction)) observedReaction.resolve(value);
    if (matches(value, reconnectedSwiftTopics.reaction)) {
      observedReconnectedReaction.resolve(value);
    }
  });
  const unsubscribeDraft = room.subscribeTopic("commentDraft", (value: any) => {
    if (matches(value, swiftTopics.commentDraft)) observedDraft.resolve(value);
    if (matches(value, reconnectedSwiftTopics.commentDraft)) {
      observedReconnectedDraft.resolve(value);
    }
  });
  const unsubscribeCommitted = room.subscribeTopic("commentCommitted", (value: any) => {
    if (matches(value, swiftTopics.commentCommitted)) observedCommitted.resolve(value);
    if (matches(value, reconnectedSwiftTopics.commentCommitted)) {
      observedReconnectedCommitted.resolve(value);
    }
  });

  try {
    const swift = runSwiftPlaybackRoom({
      appId,
      apiURI,
      websocketURI,
      refreshToken: swiftToken,
      swiftUserID: swiftUser.id,
      typeScriptUserID: typeScriptUser.id,
      roomID,
    });
    const [presence, reaction, commentDraft, commentCommitted] = await withTimeout(
      Promise.all([
        observedPresence.promise,
        observedReaction.promise,
        observedDraft.promise,
        observedCommitted.promise,
      ]),
      "observe exact Swift playback room payloads",
    );

    room.publishPresence(typeScriptPresence);
    room.publishTopic("reaction", typeScriptTopics.reaction);
    room.publishTopic("commentDraft", typeScriptTopics.commentDraft);
    room.publishTopic("commentCommitted", typeScriptTopics.commentCommitted);

    const [
      reconnectedPresence,
      reconnectedReaction,
      reconnectedCommentDraft,
      reconnectedCommentCommitted,
    ] = await withTimeout(
      Promise.all([
        observedReconnectedPresence.promise,
        observedReconnectedReaction.promise,
        observedReconnectedDraft.promise,
        observedReconnectedCommitted.promise,
      ]),
      "observe exact Swift playback room payloads after reconnect",
    );
    room.publishPresence(reconnectedTypeScriptPresence);
    room.publishTopic("reaction", reconnectedTypeScriptTopics.reaction);
    room.publishTopic("commentDraft", reconnectedTypeScriptTopics.commentDraft);
    room.publishTopic("commentCommitted", reconnectedTypeScriptTopics.commentCommitted);

    const swiftEvidence = await swift;
    assert.equal(swiftEvidence.ok, true);
    assert.equal(swiftEvidence.details.connectionState, "authenticated");
    assert.deepStrictEqual(swiftEvidence.details.publishedPresence, swiftPresence);
    assert.deepStrictEqual(swiftEvidence.details.receivedPresence, typeScriptPresence);
    assert.deepStrictEqual(swiftEvidence.details.publishedTopics, swiftTopics);
    assert.deepStrictEqual(swiftEvidence.details.receivedTopics, typeScriptTopics);
    assert.equal(swiftEvidence.details.reconnect.connectionCount, 2);
    assert.equal(swiftEvidence.details.reconnect.connectionState, "authenticated");
    assert.deepStrictEqual(
      swiftEvidence.details.reconnect.publishedPresence,
      reconnectedSwiftPresence,
    );
    assert.deepStrictEqual(
      swiftEvidence.details.reconnect.receivedPresence,
      reconnectedTypeScriptPresence,
    );
    assert.deepStrictEqual(
      swiftEvidence.details.reconnect.publishedTopics,
      reconnectedSwiftTopics,
    );
    assert.deepStrictEqual(
      swiftEvidence.details.reconnect.receivedTopics,
      reconnectedTypeScriptTopics,
    );

    process.stdout.write(`${JSON.stringify({
      case: "validation.typescript.playback-room-live-contract",
      event: "bidirectional-payloads-observed",
      side: "typescript",
      appID: appId,
      ok: true,
      details: {
        roomType: "recording.playback",
        roomID,
        swiftUserID: swiftUser.id,
        typeScriptUserID: typeScriptUser.id,
        observedSwiftPresence: presence,
        observedSwiftTopics: { reaction, commentDraft, commentCommitted },
        publishedTypeScriptPresence: typeScriptPresence,
        publishedTypeScriptTopics: typeScriptTopics,
        observedReconnectedSwiftPresence: reconnectedPresence,
        observedReconnectedSwiftTopics: {
          reaction: reconnectedReaction,
          commentDraft: reconnectedCommentDraft,
          commentCommitted: reconnectedCommentCommitted,
        },
        publishedReconnectedTypeScriptPresence: reconnectedTypeScriptPresence,
        publishedReconnectedTypeScriptTopics: reconnectedTypeScriptTopics,
        swift: swiftEvidence.details,
        compilerWarningCount: warnings.length,
        warnings,
      },
    }, null, 2)}\n`);
  } finally {
    unsubscribePresence();
    unsubscribeReaction();
    unsubscribeDraft();
    unsubscribeCommitted();
    room.leaveRoom();
    db.shutdown();
  }
} finally {
  console.warn = originalWarn;
}

function deferred<Value>(): {
  promise: Promise<Value>;
  resolve: (value: Value) => void;
} {
  let resolveValue!: (value: Value) => void;
  const promise = new Promise<Value>((resolve) => { resolveValue = resolve; });
  return { promise, resolve: resolveValue };
}

function matches(actual: unknown, expected: Record<string, unknown>): boolean {
  if (!actual || typeof actual !== "object") return false;
  const object = actual as Record<string, unknown>;
  return Object.entries(expected).every(([key, value]) => object[key] === value);
}

function unwrapSchema(module: unknown): any {
  let candidate = module;
  for (let depth = 0; depth < 4; depth += 1) {
    if (candidate && typeof candidate === "object" && "rooms" in candidate) {
      return candidate;
    }
    if (!candidate || typeof candidate !== "object" || !("default" in candidate)) break;
    candidate = (candidate as { default: unknown }).default;
  }
  throw new Error("Generated recording-action schema did not load as an Instant schema.");
}

async function withTimeout<Value>(promise: Promise<Value>, operation: string): Promise<Value> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<Value>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error(`Timed out: ${operation}.`)), 20_000);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function runSwiftPlaybackRoom(input: {
  appId: string;
  apiURI: string;
  websocketURI: string;
  refreshToken: string;
  swiftUserID: string;
  typeScriptUserID: string;
  roomID: string;
}): Promise<any> {
  const child = spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-playback-room",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: input.appId,
        INSTANT_API_URI: input.apiURI,
        INSTANT_WEBSOCKET_URI: input.websocketURI,
        INSTANT_SWIFT_DATA_PLAYBACK_REFRESH_TOKEN: input.refreshToken,
        INSTANT_SWIFT_DATA_PLAYBACK_SWIFT_USER_ID: input.swiftUserID,
        INSTANT_SWIFT_DATA_PLAYBACK_TYPESCRIPT_USER_ID: input.typeScriptUserID,
        INSTANT_SWIFT_DATA_PLAYBACK_ROOM_ID: input.roomID,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const exitCode = await new Promise<number>((resolveCode, reject) => {
    child.once("error", reject);
    child.once("close", (code) => resolveCode(code ?? 1));
  });
  if (exitCode !== 0) {
    throw new Error(
      `Swift playback room validation failed with status ${exitCode}: ${stdout.trim()} ${stderr.trim()}`,
    );
  }
  const lines = stdout.trim().split("\n").filter(Boolean);
  if (lines.length !== 1) {
    throw new Error(`Expected one Swift playback evidence row, received ${lines.length}.`);
  }
  return JSON.parse(lines[0]);
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}

// The canonical core package retains Node timers after `shutdown()`; this is a
// one-shot validation process and all evidence has been flushed synchronously.
process.exit(0);
