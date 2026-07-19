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

import { mobileChatV3AppContract } from "./mobile-chat-v3-app-contract.js";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;

interface MobileChatGraph {
  userID: string;
  profileID: string;
  displayName: string;
  channelID: string;
  channelName: string;
  messageID: string;
  messageChannelID: string;
  authorProfileID: string;
  content: string;
  timestampMilliseconds: number;
}

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const schemaPath = requiredEnvironment("INSTANT_SWIFT_DATA_MOBILE_CHAT_SCHEMA_PATH");
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
    email: `mobile-chat-swift-${suffix}@example.com`,
  });
  const typeScriptToken = await admin.auth.createToken({
    email: `mobile-chat-typescript-${suffix}@example.com`,
  });
  const swiftUser = await admin.auth.verifyToken(swiftToken);
  const typeScriptUser = await admin.auth.verifyToken(typeScriptToken);
  assert.ok(swiftUser?.id, "Expected a canonical Swift Mobile Chat user.");
  assert.ok(typeScriptUser?.id, "Expected a canonical TypeScript Mobile Chat user.");

  const swiftGraph: MobileChatGraph = {
    userID: swiftUser.id,
    profileID: randomUUID(),
    displayName: mobileChatV3AppContract.swiftCreated.profile.displayName,
    channelID: randomUUID(),
    channelName: mobileChatV3AppContract.swiftCreated.channel.name,
    messageID: randomUUID(),
    messageChannelID: "",
    authorProfileID: "",
    content: mobileChatV3AppContract.swiftCreated.message.content,
    timestampMilliseconds: mobileChatV3AppContract.swiftCreated.message.timestamp,
  };
  swiftGraph.messageChannelID = swiftGraph.channelID;
  swiftGraph.authorProfileID = swiftGraph.profileID;
  const typeScriptGraph: MobileChatGraph = {
    userID: typeScriptUser.id,
    profileID: randomUUID(),
    displayName: mobileChatV3AppContract.typeScriptCreated.profile.displayName,
    channelID: randomUUID(),
    channelName: mobileChatV3AppContract.typeScriptCreated.channel.name,
    messageID: randomUUID(),
    messageChannelID: "",
    authorProfileID: "",
    content: mobileChatV3AppContract.typeScriptCreated.message.content,
    timestampMilliseconds: mobileChatV3AppContract.typeScriptCreated.message.timestamp,
  };
  typeScriptGraph.messageChannelID = typeScriptGraph.channelID;
  typeScriptGraph.authorProfileID = typeScriptGraph.profileID;

  const schemaModule = await import(pathToFileURL(schemaPath).href);
  const schema = unwrapSchema(schemaModule);
  (globalThis as any).window = globalThis;
  (globalThis as any).BroadcastChannel = undefined;

  const anonymous = initCore(
    { appId, apiURI, websocketURI, schema, devtool: false },
    MemoryStore,
    AlwaysOnline,
  );
  let anonymousRejection = "";
  try {
    await anonymous.transact(
      anonymous.tx.channels[randomUUID()].create({ name: "Denied channel" }),
    );
  } catch (error) {
    anonymousRejection = String(error);
  } finally {
    anonymous.shutdown();
  }
  assert.notEqual(anonymousRejection, "", "Expected unauthenticated channel creation denial.");

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

  const observer = spawnSwift("--live-mobile-chat-v3-observe", {
    appId,
    apiURI,
    websocketURI,
    refreshToken: typeScriptToken,
    graph: typeScriptGraph,
  });
  const lines = createInterface({ input: observer.stdout, crlfDelay: Infinity })
    [Symbol.asyncIterator]();
  const ready = await nextJSONLine(lines, observer, "Swift Mobile Chat observer readiness");
  assert.equal(ready.event, "observer-ready");
  assert.equal(ready.details.connectionState, "authenticated");

  const room: any = db.joinRoom(mobileChatV3AppContract.room.type, swiftGraph.channelID);
  const observedSwiftPresence = deferred<{ profileId: string; displayName: string }>();
  const observedSwiftTyping = deferred<typeof mobileChatV3AppContract.room.swiftTyping>();
  const observedSwiftReaction = deferred<typeof mobileChatV3AppContract.room.swiftReaction>();
  const swiftCleanupAcknowledged = deferred<void>();
  const unsubscribePresence = room.subscribePresence({}, (presence: any) => {
    for (const peer of Object.values(presence.peers ?? {})) {
      if (matches(peer, {
        profileId: swiftGraph.profileID,
        displayName: mobileChatV3AppContract.room.swiftPresence.displayName,
      })) {
        observedSwiftPresence.resolve({
          profileId: swiftGraph.profileID,
          displayName: mobileChatV3AppContract.room.swiftPresence.displayName,
        });
      }
    }
  });
  const unsubscribeTyping = room.subscribeTopic("typing", (value: any) => {
    if (matches(value, mobileChatV3AppContract.room.swiftTyping)) {
      observedSwiftTyping.resolve(mobileChatV3AppContract.room.swiftTyping);
    }
  });
  const unsubscribeEmoji = room.subscribeTopic("emoji", (value: any) => {
    if (matches(value, mobileChatV3AppContract.room.swiftReaction)) {
      observedSwiftReaction.resolve(mobileChatV3AppContract.room.swiftReaction);
    }
    if (matches(value, { name: "confetti", directionAngle: 0, rotationAngle: 0 })) {
      swiftCleanupAcknowledged.resolve();
    }
  });

  try {
    const swiftWrite = runSwiftWrite({
      appId,
      apiURI,
      websocketURI,
      refreshToken: swiftToken,
      graph: swiftGraph,
      peerProfileID: typeScriptGraph.profileID,
    });
    const [swiftPresence, swiftTyping, swiftReaction] = await withTimeout(
      Promise.all([
        observedSwiftPresence.promise,
        observedSwiftTyping.promise,
        observedSwiftReaction.promise,
      ]),
      "observe exact Swift Mobile Chat room payloads",
    );

    const typeScriptPresence = {
      ...mobileChatV3AppContract.room.typeScriptPresence,
      profileId: typeScriptGraph.profileID,
    };
    room.publishPresence(typeScriptPresence);
    room.publishTopic("typing", mobileChatV3AppContract.room.typeScriptTyping);
    room.publishTopic("emoji", mobileChatV3AppContract.room.typeScriptReaction);
    await withTimeout(
      swiftCleanupAcknowledged.promise,
      "wait for Swift Mobile Chat cleanup acknowledgement",
    );
    room.leaveRoom();

    const swiftEvidence = await swiftWrite;
    assert.equal(swiftEvidence.ok, true);
    assert.equal(swiftEvidence.event, "swift-graph-and-room-observed");
    assert.deepEqual(swiftEvidence.details.graph, {
      direction: "swift-to-typescript",
      ...swiftGraph,
      connectionState: "authenticated",
      pendingMutationCount: 0,
    });
    assert.deepEqual(swiftEvidence.details.room, {
      roomType: "chat",
      roomID: swiftGraph.channelID,
      peerCount: 2,
      presence: {
        profileId: swiftGraph.profileID,
        displayName: swiftGraph.displayName,
      },
      typing: mobileChatV3AppContract.room.swiftTyping,
      emoji: mobileChatV3AppContract.room.swiftReaction,
      peerCountAfterDisconnect: 1,
      receivedPresence: typeScriptPresence,
      receivedTyping: mobileChatV3AppContract.room.typeScriptTyping,
      receivedEmoji: mobileChatV3AppContract.room.typeScriptReaction,
    });

    const typeScriptObserved = await waitForGraph(db, swiftGraph);
    assert.deepEqual(typeScriptObserved, swiftGraph);

    await db.transact([
      db.tx.profiles[typeScriptGraph.profileID]
        .create({ displayName: typeScriptGraph.displayName })
        .link({ user: typeScriptGraph.userID }),
      db.tx.channels[typeScriptGraph.channelID]
        .create({ name: typeScriptGraph.channelName }),
      db.tx.messages[typeScriptGraph.messageID]
        .create({
          content: typeScriptGraph.content,
          timestamp: typeScriptGraph.timestampMilliseconds,
        })
        .link({ author: typeScriptGraph.authorProfileID })
        .link({ channel: typeScriptGraph.messageChannelID }),
    ]);

    const swiftObserved = await nextJSONLine(
      lines,
      observer,
      "Swift observation of TypeScript Mobile Chat graph",
    );
    assert.equal(swiftObserved.event, "typescript-graph-observed");
    assert.deepEqual(swiftObserved.details, {
      direction: "typescript-to-swift",
      ...typeScriptGraph,
      connectionState: "authenticated",
      pendingMutationCount: 0,
    });
    await requireSuccessfulExit(observer, "Swift Mobile Chat observer");

    assert.deepEqual(warnings, []);
    process.stdout.write(`${JSON.stringify({
      case: "validation.typescript.mobile-chat-v3-live-contract",
      event: "bidirectional-mobile-chat-observed",
      side: "typescript",
      appID: appId,
      ok: true,
      details: {
        upstream: mobileChatV3AppContract.upstream,
        users: {
          swift: { id: swiftUser.id, email: swiftUser.email },
          typeScript: { id: typeScriptUser.id, email: typeScriptUser.email },
        },
        swift: swiftEvidence.details.graph,
        typeScriptObserved,
        typeScriptCreated: typeScriptGraph,
        swiftObserved: swiftObserved.details,
        room: {
          observedSwiftPresence: swiftPresence,
          observedSwiftTyping: swiftTyping,
          observedSwiftReaction: swiftReaction,
          ...swiftEvidence.details.room,
        },
        permissions: {
          anonymousCreateRejected: true,
          rejection: anonymousRejection,
        },
        compilerWarningCount: warnings.length,
        warnings,
      },
    }, null, 2)}\n`);
    db.shutdown();
  } finally {
    unsubscribePresence();
    unsubscribeTyping();
    unsubscribeEmoji();
  }
} finally {
  console.warn = originalWarn;
}

async function waitForGraph(db: any, expected: MobileChatGraph): Promise<MobileChatGraph> {
  let last: unknown;
  for (let attempt = 0; attempt < 150; attempt += 1) {
    const result = await db.queryOnce({
      messages: {
        $: { where: { id: expected.messageID } },
        author: { user: {} },
        channel: {},
      },
    });
    last = result.data;
    const message = result.data.messages?.[0];
    if (
      message?.id === expected.messageID
      && message?.content === expected.content
      && message?.timestamp === expected.timestampMilliseconds
      && message?.channel?.id === expected.channelID
      && message?.channel?.name === expected.channelName
      && message?.author?.id === expected.profileID
      && message?.author?.displayName === expected.displayName
      && message?.author?.user?.id === expected.userID
    ) {
      return {
        userID: message.author.user.id,
        profileID: message.author.id,
        displayName: message.author.displayName,
        channelID: message.channel.id,
        channelName: message.channel.name,
        messageID: message.id,
        messageChannelID: message.channel.id,
        authorProfileID: message.author.id,
        content: message.content,
        timestampMilliseconds: message.timestamp,
      };
    }
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 100));
  }
  throw new Error(`Timed out waiting for canonical Mobile Chat graph: ${JSON.stringify(last)}`);
}

async function runSwiftWrite(input: SwiftInput): Promise<any> {
  const child = spawnSwift("--live-mobile-chat-v3-write", input);
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const exitCode = await withTimeout(childExit(child), "Swift Mobile Chat writer exit");
  if (exitCode !== 0) {
    throw new Error(
      `Swift Mobile Chat writer failed with status ${exitCode}: ${stdout.trim()} ${stderr.trim()}`,
    );
  }
  const lines = stdout.trim().split("\n").filter(Boolean);
  assert.equal(lines.length, 1, "Expected one Swift Mobile Chat writer evidence row.");
  return JSON.parse(lines[0]);
}

interface SwiftInput {
  appId: string;
  apiURI: string;
  websocketURI: string;
  refreshToken: string;
  graph: MobileChatGraph;
  peerProfileID?: string;
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
        INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_REFRESH_TOKEN: input.refreshToken,
        INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_USER_ID: input.graph.userID,
        INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_PROFILE_ID: input.graph.profileID,
        INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_DISPLAY_NAME: input.graph.displayName,
        INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_CHANNEL_ID: input.graph.channelID,
        INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_CHANNEL_NAME: input.graph.channelName,
        INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_MESSAGE_ID: input.graph.messageID,
        INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_CONTENT: input.graph.content,
        INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_TIMESTAMP_MILLISECONDS:
          String(input.graph.timestampMilliseconds),
        INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_PEER_PROFILE_ID: input.peerProfileID ?? "",
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

function deferred<Value>(): { promise: Promise<Value>; resolve: (value: Value) => void } {
  let resolveValue!: (value: Value) => void;
  const promise = new Promise<Value>((resolveValuePromise) => {
    resolveValue = resolveValuePromise;
  });
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
    if (candidate && typeof candidate === "object" && "entities" in candidate) {
      return candidate;
    }
    if (!candidate || typeof candidate !== "object" || !("default" in candidate)) break;
    candidate = (candidate as { default: unknown }).default;
  }
  throw new Error("Generated Mobile Chat schema did not load as an Instant schema.");
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

process.exit(0);
