import assert from "node:assert/strict";
import { spawn, type ChildProcessByStdio } from "node:child_process";
import { randomUUID } from "node:crypto";
import { rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
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

import { remindersV3AppContract } from "./reminders-v3-app-contract.js";
import { projectCanonicalRemindersV3List } from "./reminders-v3-live-support.js";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;
type CanonicalList = ReturnType<typeof projectCanonicalRemindersV3List>;

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const schemaPath = requiredEnvironment("INSTANT_SWIFT_DATA_REMINDERS_SCHEMA_PATH");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI
  ?? "wss://api.instantdb.com/runtime/session";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const readerCheckSignal = resolve(tmpdir(), `reminders-reader-check-${randomUUID()}`);
const fixtures = {
  list: randomUUID(),
  swiftReminder: randomUUID(),
  share: randomUUID(),
  ownerMembership: randomUUID(),
  readerMembership: randomUUID(),
  typeScriptReminder: randomUUID(),
  swiftTag: randomUUID(),
  typeScriptTag: randomUUID(),
  swiftTagTitle: `swift-${randomUUID()}`,
  typeScriptTagTitle: `typescript-${randomUUID()}`,
  shareToken: `reminders-v3-${randomUUID()}`,
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

let swift: SwiftProcess | undefined;
const databases: any[] = [];

try {
  const suffix = randomUUID();
  const swiftEmail = `reminders-swift-${suffix}@example.com`;
  const swiftDisplayName = "Swift Reminders Owner";
  const swiftUsername = `swift-${suffix}`;
  const typeScriptEmail = `reminders-typescript-${suffix}@example.com`;
  const typeScriptDisplayName = "TypeScript Reminders Collaborator";
  const typeScriptUsername = `typescript-${suffix}`;
  const outsiderEmail = `reminders-outsider-${suffix}@example.com`;
  const admin = initAdmin({ appId, adminToken, apiURI });
  const swiftToken = await withRetries(
    () => admin.auth.createToken({ email: swiftEmail }),
    "create Swift Reminders token",
  );
  const typeScriptToken = await withRetries(
    () => admin.auth.createToken({ email: typeScriptEmail }),
    "create TypeScript Reminders token",
  );
  const outsiderToken = await withRetries(
    () => admin.auth.createToken({ email: outsiderEmail }),
    "create outsider Reminders token",
  );
  const swiftUser = await withRetries(
    () => admin.auth.verifyToken(swiftToken),
    "verify Swift Reminders token",
  );
  const typeScriptUser = await withRetries(
    () => admin.auth.verifyToken(typeScriptToken),
    "verify TypeScript Reminders token",
  );
  const outsiderUser = await withRetries(
    () => admin.auth.verifyToken(outsiderToken),
    "verify outsider Reminders token",
  );
  assert.ok(swiftUser?.id, "Expected a canonical Swift Reminders owner.");
  assert.ok(typeScriptUser?.id, "Expected a canonical TypeScript Reminders participant.");
  assert.ok(outsiderUser?.id, "Expected a canonical Reminders outsider.");
  await withRetries(
    () => admin.transact([
      admin.tx.$users[swiftUser.id].update({
        displayName: swiftDisplayName,
        username: swiftUsername,
      }),
      admin.tx.$users[typeScriptUser.id].update({
        displayName: typeScriptDisplayName,
        username: typeScriptUsername,
      }),
    ]),
    "attach Reminders user profiles",
  );

  const schema = unwrapSchema(await import(pathToFileURL(schemaPath).href));
  (globalThis as any).window = globalThis;
  (globalThis as any).BroadcastChannel = undefined;
  (globalThis as any).WebSocket = WebSocket;
  const participantDB = coreDatabase(schema);
  const outsiderDB = admin.asUser({ token: outsiderToken });
  databases.push(participantDB);
  await participantDB.auth.signInWithToken(typeScriptToken);

  swift = spawnSwift({
    refreshToken: swiftToken,
    ownerUserID: swiftUser.id,
    ownerEmail: swiftEmail,
    ownerDisplayName: swiftDisplayName,
    ownerUsername: swiftUsername,
    participantUserID: typeScriptUser.id,
    participantEmail: typeScriptEmail,
    participantDisplayName: typeScriptDisplayName,
    participantUsername: typeScriptUsername,
  });
  const lines = createInterface({ input: swift.stdout, crlfDelay: Infinity })
    [Symbol.asyncIterator]();

  const graphReady = await nextJSONLine(lines, swift, "Swift Reminders graph readiness");
  assert.equal(graphReady.event, "swift-graph-ready", JSON.stringify(graphReady));
  assert.equal(graphReady.ok, true);

  const readerObserved = await nextJSONLine(
    lines,
    swift,
    "Swift acceptance of TypeScript Reminders reader membership",
  );
  assert.equal(readerObserved.event, "typescript-reader-observed", JSON.stringify(readerObserved));
  assert.equal(readerObserved.ok, true);
  const adminReaderGraph = await admin.query(remindersListQuery());
  assert.equal(
    adminReaderGraph.remindersLists.length,
    1,
    `Admin did not observe the accepted Reminders graph: ${JSON.stringify(adminReaderGraph)}`,
  );
  const participantAdminDB = admin.asUser({ token: typeScriptToken });
  const scopedReaderGraph = await participantAdminDB.query(remindersListQuery());
  assert.equal(
    scopedReaderGraph.remindersLists.length,
    1,
    `Participant permissions hid the accepted Reminders graph: ${JSON.stringify(adminReaderGraph)}`,
  );
  const readerList = await waitForList(participantDB, (list) => (
    list.owner.id === swiftUser.id
    && list.readers.some((user) => user.id === typeScriptUser.id)
    && list.share?.memberships.some((membership) => (
      membership.user.id === typeScriptUser.id && membership.role === "reader"
    )) === true
    && list.reminders.some((reminder) => (
      reminder.id === fixtures.swiftReminder
      && reminder.priority === remindersV3AppContract.priority.high
      && reminder.tags.some((tag) => tag.id === fixtures.swiftTag)
    ))
  ));
  const swiftList = readerList;
  const readerUpdateRejection = await rejected(
    participantDB.transact(
      participantDB.tx.reminders[fixtures.swiftReminder]
        .update({ title: "Reader must not update" }),
    ),
  );
  assert.match(readerUpdateRejection, /permission|reminder|update/i);
  await writeFile(readerCheckSignal, "reader update rejected\n", "utf8");

  const writerReady = await nextJSONLine(lines, swift, "Swift Reminders writer promotion");
  assert.equal(writerReady.event, "swift-writer-promotion-ready", JSON.stringify(writerReady));
  assert.equal(writerReady.ok, true);
  const writerList = await waitForList(participantDB, (list) => (
    list.readers.every((user) => user.id !== typeScriptUser.id)
    && list.writers.some((user) => user.id === typeScriptUser.id)
    && list.share?.memberships.some((membership) => (
      membership.user.id === typeScriptUser.id && membership.role === "writer"
    )) === true
  ));

  await participantDB.transact([
    participantDB.tx.tags[fixtures.typeScriptTag].update({
      title: fixtures.typeScriptTagTitle,
    }),
    participantDB.tx.reminders[fixtures.swiftReminder].update({
      title: "Swift reminder updated by TypeScript",
    }),
    participantDB.tx.reminders[fixtures.typeScriptReminder]
      .update({
        title: "TypeScript reminder",
        notes: "Created by @instantdb/core",
        isCompleted: false,
        isFlagged: false,
        priority: remindersV3AppContract.priority.medium,
        position: 1,
        createdAt: new Date(1_784_424_002_000),
      })
      .link({
        list: fixtures.list,
        tags: fixtures.typeScriptTag,
      }),
  ]);

  const reminderObserved = await nextJSONLine(
    lines,
    swift,
    "Swift observation of TypeScript Reminders writes",
  );
  assert.equal(reminderObserved.event, "typescript-reminder-observed", JSON.stringify(reminderObserved));
  assert.equal(reminderObserved.ok, true);
  const completedList = await waitForList(participantDB, (list) => (
    list.reminders.some((reminder) => (
      reminder.id === fixtures.swiftReminder
      && reminder.title === "Swift reminder updated by TypeScript"
    ))
    && list.reminders.some((reminder) => (
      reminder.id === fixtures.typeScriptReminder
      && reminder.priority === remindersV3AppContract.priority.medium
      && reminder.tags.some((tag) => tag.id === fixtures.typeScriptTag)
    ))
  ));
  const outsiderResult = await outsiderDB.query(remindersListQuery());
  assert.deepEqual(outsiderResult.remindersLists, []);

  const swiftEvidence = await nextJSONLine(lines, swift, "Swift Reminders evidence");
  await requireSuccessfulExit(swift, "Swift Reminders runner");
  swift = undefined;
  assert.equal(swiftEvidence.ok, true);
  assert.equal(swiftEvidence.event, "typescript-writer-reminder-observed");
  assert.equal(swiftEvidence.details.pendingMutationCount, 0);
  assert.equal(swiftEvidence.details.connectionState, "authenticated");
  assert.deepEqual(swiftEvidence.details.authenticatedUser, {
    id: swiftUser.id,
    email: swiftEmail,
    displayName: swiftDisplayName,
    username: swiftUsername,
  });
  assert.deepEqual(swiftEvidence.details.participantDirectoryUser, {
    id: typeScriptUser.id,
    email: typeScriptEmail,
    displayName: typeScriptDisplayName,
    username: typeScriptUsername,
  });
  assert.equal(
    swiftEvidence.details.swiftReminder.title,
    "Swift reminder updated by TypeScript",
  );
  assert.equal(
    swiftEvidence.details.typeScriptReminderObservedBySwift.priority,
    remindersV3AppContract.priority.medium,
  );
  assert.deepEqual(warnings, []);

  const output = {
    case: "validation.typescript.reminders-v3-live-contract",
    event: "bidirectional-sharing-and-reminders-observed",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      upstream: remindersV3AppContract.upstream,
      fixtureIDs: {
        list: fixtures.list,
        swiftReminder: fixtures.swiftReminder,
        typeScriptReminder: fixtures.typeScriptReminder,
        typeScriptTag: fixtures.typeScriptTag,
      },
      users: {
        owner: {
          id: swiftUser.id,
          email: swiftEmail,
          displayName: swiftDisplayName,
          username: swiftUsername,
        },
        participant: {
          id: typeScriptUser.id,
          email: typeScriptEmail,
          displayName: typeScriptDisplayName,
          username: typeScriptUsername,
        },
        outsider: { id: outsiderUser.id, email: outsiderEmail },
      },
      typeScriptObservedSwiftList: swiftList,
      typeScriptObservedReaderList: readerList,
      typeScriptObservedWriterList: writerList,
      typeScriptObservedFinalList: completedList,
      outsiderVisibleListCount: outsiderResult.remindersLists.length,
      readerUpdateRejection,
      swift: swiftEvidence.details,
      compilerWarningCount: warnings.length,
      warnings,
    },
  };
  const serialized = JSON.stringify(output);
  assert.equal(serialized.includes("refresh_token"), false);
  assert.equal(serialized.includes(adminToken), false);
  await writeStdout(`${JSON.stringify(output, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
  await rm(readerCheckSignal, { force: true });
  for (const database of databases) database.shutdown();
  if (swift && swift.exitCode === null) swift.kill();
}
process.exit(0);

function coreDatabase(schema: any): any {
  return initCore(
    { appId, apiURI, websocketURI, schema, devtool: false, useDateObjects: true },
    MemoryStore,
    AlwaysOnline,
  );
}

function remindersListQuery(): any {
  return {
    remindersLists: {
      $: { where: { id: fixtures.list } },
      owner: {},
      readers: {},
      writers: {},
      reminders: { tags: {} },
      share: { owner: {}, memberships: { user: {} } },
    },
  };
}

async function waitForList(
  database: any,
  predicate: (list: CanonicalList) => boolean,
): Promise<CanonicalList> {
  let last: unknown;
  for (let attempt = 0; attempt < 300; attempt += 1) {
    const result = await database.queryOnce(remindersListQuery());
    last = result.data;
    const rawList = result.data.remindersLists?.[0];
    if (rawList) {
      let list: CanonicalList;
      try {
        list = projectCanonicalRemindersV3List(rawList);
      } catch (error) {
        throw new Error(
          `Could not project canonical Reminders list: ${String(error)}; raw=${JSON.stringify(rawList)}`,
        );
      }
      if (predicate(list)) return list;
    }
    await delay();
  }
  throw new Error(`Timed out waiting for canonical Reminders list: ${JSON.stringify(last)}`);
}

function spawnSwift(
  input: {
    refreshToken: string;
    ownerUserID: string;
    ownerEmail: string;
    ownerDisplayName: string;
    ownerUsername: string;
    participantUserID: string;
    participantEmail: string;
    participantDisplayName: string;
    participantUsername: string;
  },
): SwiftProcess {
  return spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-reminders-v3",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: appId,
        INSTANT_API_URI: apiURI,
        INSTANT_WEBSOCKET_URI: websocketURI,
        INSTANT_SWIFT_DATA_REMINDERS_REFRESH_TOKEN: input.refreshToken,
        INSTANT_SWIFT_DATA_REMINDERS_OWNER_USER_ID: input.ownerUserID,
        INSTANT_SWIFT_DATA_REMINDERS_OWNER_EMAIL: input.ownerEmail,
        INSTANT_SWIFT_DATA_REMINDERS_OWNER_DISPLAY_NAME: input.ownerDisplayName,
        INSTANT_SWIFT_DATA_REMINDERS_OWNER_USERNAME: input.ownerUsername,
        INSTANT_SWIFT_DATA_REMINDERS_PARTICIPANT_USER_ID: input.participantUserID,
        INSTANT_SWIFT_DATA_REMINDERS_PARTICIPANT_EMAIL: input.participantEmail,
        INSTANT_SWIFT_DATA_REMINDERS_PARTICIPANT_DISPLAY_NAME:
          input.participantDisplayName,
        INSTANT_SWIFT_DATA_REMINDERS_PARTICIPANT_USERNAME: input.participantUsername,
        INSTANT_SWIFT_DATA_REMINDERS_LIST_ID: fixtures.list,
        INSTANT_SWIFT_DATA_REMINDERS_SWIFT_REMINDER_ID: fixtures.swiftReminder,
        INSTANT_SWIFT_DATA_REMINDERS_SHARE_ID: fixtures.share,
        INSTANT_SWIFT_DATA_REMINDERS_OWNER_MEMBERSHIP_ID: fixtures.ownerMembership,
        INSTANT_SWIFT_DATA_REMINDERS_READER_MEMBERSHIP_ID: fixtures.readerMembership,
        INSTANT_SWIFT_DATA_REMINDERS_TYPESCRIPT_REMINDER_ID: fixtures.typeScriptReminder,
        INSTANT_SWIFT_DATA_REMINDERS_SWIFT_TAG_ID: fixtures.swiftTag,
        INSTANT_SWIFT_DATA_REMINDERS_TYPESCRIPT_TAG_ID: fixtures.typeScriptTag,
        INSTANT_SWIFT_DATA_REMINDERS_SWIFT_TAG_TITLE: fixtures.swiftTagTitle,
        INSTANT_SWIFT_DATA_REMINDERS_SHARE_TOKEN: fixtures.shareToken,
        INSTANT_SWIFT_DATA_REMINDERS_READER_CHECK_SIGNAL: readerCheckSignal,
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
  throw new Error("Generated Reminders schema did not load.");
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

async function rejected(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
  } catch (error) {
    return String(error);
  }
  throw new Error("Expected the reader operation to be rejected by permissions.");
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

async function withRetries<T>(
  operation: () => Promise<T>,
  label: string,
): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (attempt < 2) {
        await new Promise((resolveRetry) => setTimeout(resolveRetry, 250 * (attempt + 1)));
      }
    }
  }
  throw new Error(`${label} failed after three attempts: ${String(lastError)}`);
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
