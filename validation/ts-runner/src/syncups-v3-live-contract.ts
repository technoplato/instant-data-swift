import assert from "node:assert/strict";
import { spawn, type ChildProcessByStdio } from "node:child_process";
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

import { syncUpsV3AppContract } from "./syncups-v3-app-contract.js";
import { projectCanonicalSyncUpsV3SyncUp } from "./syncups-v3-live-support.js";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;
type CanonicalSyncUp = ReturnType<typeof projectCanonicalSyncUpsV3SyncUp>;

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const schemaPath = requiredEnvironment("INSTANT_SWIFT_DATA_SYNCUPS_SCHEMA_PATH");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI
  ?? "wss://api.instantdb.com/runtime/session";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const swiftMeetingDate = new Date(1_784_467_200_000);
const typeScriptMeetingDate = new Date(1_784_467_201_000);
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
  const admin = initAdmin({ appId, adminToken, apiURI });
  const refreshToken = await admin.auth.createToken({
    email: `syncups-v3-${appId}@example.com`,
  });
  const user = await admin.auth.verifyToken(refreshToken);
  assert.ok(user?.id, "Expected a canonical SyncUps V3 user.");

  const schema = unwrapSchema(await import(pathToFileURL(schemaPath).href));
  (globalThis as any).window = globalThis;
  (globalThis as any).BroadcastChannel = undefined;
  (globalThis as any).WebSocket = WebSocket;
  db = initCore(
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

  swift = spawnSwift(refreshToken, user.id);
  const lines = createInterface({ input: swift.stdout, crlfDelay: Infinity })
    [Symbol.asyncIterator]();
  const ready = await nextJSONLine(lines, swift, "Swift SyncUps graph readiness");
  assert.equal(ready.event, "swift-graph-ready", JSON.stringify(ready));
  assert.equal(ready.ok, true);

  const swiftGraph = await waitForSyncUp(db, (syncUp) => (
    syncUp.title === "Design"
    && syncUp.attendees.some((attendee) => (
      attendee.id === syncUpsV3AppContract.fixtures.swiftAttendee
      && attendee.name === "Blob"
    ))
    && syncUp.meetings.some((meeting) => (
      meeting.id === syncUpsV3AppContract.fixtures.swiftMeeting
      && meeting.date.getTime() === swiftMeetingDate.getTime()
      && meeting.transcript === "Reviewed launch risks."
    ))
  ));

  await db.transact([
    db.tx.syncUps[syncUpsV3AppContract.fixtures.syncUp].update({
      title: "Design updated by TypeScript",
    }),
    db.tx.attendees[syncUpsV3AppContract.fixtures.typeScriptAttendee]
      .update({ name: "Blob Jr" })
      .link({ syncUp: syncUpsV3AppContract.fixtures.syncUp }),
    db.tx.meetings[syncUpsV3AppContract.fixtures.typeScriptMeeting]
      .update({
        date: typeScriptMeetingDate,
        transcript: "TypeScript follow-up notes.",
      })
      .link({ syncUp: syncUpsV3AppContract.fixtures.syncUp }),
  ]);

  const observed = await nextJSONLine(lines, swift, "Swift SyncUps TypeScript observation");
  assert.equal(observed.event, "typescript-graph-observed", JSON.stringify(observed));
  assert.equal(observed.ok, true);
  const swiftEvidence = await nextJSONLine(lines, swift, "Swift SyncUps final evidence");
  await requireSuccessfulExit(swift, "Swift SyncUps runner");
  swift = undefined;
  assert.equal(swiftEvidence.event, "typescript-graph-observed");
  assert.equal(swiftEvidence.ok, true);
  assert.equal(swiftEvidence.details.connectionState, "authenticated");
  assert.equal(swiftEvidence.details.pendingMutationCount, 0);
  assert.equal(swiftEvidence.details.title, "Design updated by TypeScript");
  assert.deepEqual(swiftEvidence.details.attendeeIDs, [
    syncUpsV3AppContract.fixtures.swiftAttendee,
    syncUpsV3AppContract.fixtures.typeScriptAttendee,
  ]);
  assert.deepEqual(swiftEvidence.details.attendeeNames, ["Blob", "Blob Jr"]);

  const finalGraph = await waitForSyncUp(db, (syncUp) => (
    syncUp.title === "Design updated by TypeScript"
    && syncUp.attendees.length === 2
    && syncUp.meetings.length === 2
  ));
  assert.deepEqual(warnings, []);

  const output = {
    case: "validation.typescript.syncups-v3-live-contract",
    event: "bidirectional-syncups-observed",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      user: { id: user.id, email: user.email },
      typeScriptObservedSwiftGraph: swiftGraph,
      typeScriptObservedFinalGraph: finalGraph,
      swift: swiftEvidence.details,
      compilerWarningCount: warnings.length,
      warnings,
    },
  };
  const serialized = JSON.stringify(output);
  assert.equal(serialized.includes("refresh_token"), false);
  assert.equal(serialized.includes(adminToken), false);
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
  db?.shutdown();
  if (swift && swift.exitCode === null) swift.kill();
}

function syncUpQuery(): any {
  return {
    syncUps: {
      $: { where: { id: syncUpsV3AppContract.fixtures.syncUp } },
      attendees: {},
      meetings: {},
    },
  };
}

async function waitForSyncUp(
  database: any,
  predicate: (syncUp: CanonicalSyncUp) => boolean,
): Promise<CanonicalSyncUp> {
  let last: unknown;
  for (let attempt = 0; attempt < 300; attempt += 1) {
    const result = await database.queryOnce(syncUpQuery());
    last = result.data;
    const raw = result.data.syncUps?.[0];
    if (raw) {
      const syncUp = projectCanonicalSyncUpsV3SyncUp(raw);
      if (predicate(syncUp)) return syncUp;
    }
    await delay();
  }
  throw new Error(`Timed out waiting for canonical SyncUps graph: ${JSON.stringify(last)}`);
}

function spawnSwift(refreshToken: string, userID: string): SwiftProcess {
  return spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-syncups-v3",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: appId,
        INSTANT_API_URI: apiURI,
        INSTANT_WEBSOCKET_URI: websocketURI,
        INSTANT_SWIFT_DATA_SYNCUPS_REFRESH_TOKEN: refreshToken,
        INSTANT_SWIFT_DATA_SYNCUPS_USER_ID: userID,
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

function unwrapSchema(module: unknown): any {
  let candidate = module;
  for (let depth = 0; depth < 4; depth += 1) {
    if (candidate && typeof candidate === "object" && "entities" in candidate) {
      return candidate;
    }
    if (!candidate || typeof candidate !== "object" || !("default" in candidate)) break;
    candidate = (candidate as { default: unknown }).default;
  }
  throw new Error("Generated SyncUps schema did not load as an Instant schema.");
}

function childExit(child: SwiftProcess): Promise<number> {
  if (child.exitCode !== null) return Promise.resolve(child.exitCode);
  return new Promise((resolveCode, reject) => {
    child.once("error", reject);
    child.once("close", (code) => resolveCode(code ?? 1));
  });
}

async function withTimeout<T>(promise: Promise<T>, operation: string): Promise<T> {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<never>((_, reject) => {
        timeout = setTimeout(
          () => reject(new Error(`${operation} timed out.`)),
          60_000,
        );
      }),
    ]);
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}

function delay(): Promise<void> {
  return new Promise((resolveDelay) => setTimeout(resolveDelay, 100));
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}
