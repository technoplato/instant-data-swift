import assert from "node:assert/strict";
import { spawn, type ChildProcessByStdio } from "node:child_process";
import { randomUUID } from "node:crypto";
import { dirname, resolve } from "node:path";
import { createInterface } from "node:readline";
import type { Readable } from "node:stream";
import { fileURLToPath } from "node:url";
import { init } from "@instantdb/admin";

import { sharingQuery } from "./sharing-sdk-contract.js";
import { sharingRuntimeSchema } from "./sharing-runtime-schema.js";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI
  ?? "wss://api.instantdb.com/runtime/session";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const suffix = randomUUID();
const ids = {
  counterID: randomUUID(),
  shareID: randomUUID(),
  ownerMembershipID: randomUUID(),
  readerMembershipID: randomUUID(),
  writerMembershipID: randomUUID(),
};
const warnings: string[] = [];
const originalWarn = console.warn;
console.warn = (...values) => warnings.push(values.map(String).join(" "));

try {
  const admin = init({
    appId,
    adminToken,
    apiURI,
    schema: sharingRuntimeSchema,
    useDateObjects: true,
  });
  const identities = await Promise.all(
    (["owner", "reader", "writer", "outsider"] as const).map(async (role) => {
      const email = `cloudkit-demo-v3-${role}-${suffix}@example.com`;
      const token = await admin.auth.createToken({ email });
      const user = await admin.auth.verifyToken(token);
      assert.ok(user?.id, `Expected canonical ${role} identity.`);
      return [role, { id: user.id, email, token }] as const;
    }),
  );
  const users = Object.fromEntries(identities) as Record<
    "owner" | "reader" | "writer" | "outsider",
    { id: string; email: string; token: string }
  >;
  const ownerDB = admin.asUser({ token: users.owner.token });
  const readerDB = admin.asUser({ token: users.reader.token });
  const writerDB = admin.asUser({ token: users.writer.token });
  const outsiderDB = admin.asUser({ token: users.outsider.token });
  const swift = spawnSwift({ appId, apiURI, websocketURI, ids, users });
  const lines = createInterface({ input: swift.stdout, crlfDelay: Infinity })
    [Symbol.asyncIterator]();

  const ready = await nextJSONLine(lines, swift, "Swift shared-counter readiness");
  assert.equal(ready.event, "typescript-writer-ready");
  assert.equal(ready.details.counterID, ids.counterID);

  const beforeTypeScriptIncrement = snapshot(
    await writerDB.query(sharingQuery(ids.counterID)),
  );
  assert.equal(beforeTypeScriptIncrement.value, 1);
  assert.deepStrictEqual(beforeTypeScriptIncrement.roles, ["writer"]);

  await writerDB.transact(
    writerDB.tx.v3_shared_lists[ids.counterID].update({ value: 2 }),
  );

  const swiftEvidence = await nextJSONLine(lines, swift, "Swift shared-counter evidence");
  await requireSuccessfulExit(swift, "Swift CloudKitDemo V3 runner");
  assert.equal(swiftEvidence.ok, true);
  assert.equal(swiftEvidence.details.counterID, ids.counterID);
  assert.equal(swiftEvidence.details.shareID, ids.shareID);
  assert.equal(swiftEvidence.details.ownerUserID, users.owner.id);
  assert.equal(swiftEvidence.details.readerUserID, users.reader.id);
  assert.equal(swiftEvidence.details.writerUserID, users.writer.id);
  assert.deepStrictEqual(swiftEvidence.details.ownerObservedValues, [0, 1, 2]);
  assert.deepStrictEqual(swiftEvidence.details.readerObservedValues, [0, 1, 0, 1, 2, 3, 2]);
  assert.match(swiftEvidence.details.firstReaderFailure, /permission/i);
  assert.match(swiftEvidence.details.secondReaderFailure, /permission/i);
  assert.equal(swiftEvidence.details.readerVisibleAfterRevocation, false);
  assert.equal(swiftEvidence.details.relaunchedValue, 2);
  assert.deepStrictEqual(swiftEvidence.details.relaunchedRoles, ["owner", "writer"]);
  assert.deepStrictEqual(swiftEvidence.details.relaunchedPublicShareRoles, ["owner", "writer"]);
  assert.equal(swiftEvidence.details.pendingMutationCount, 0);
  assert.equal(swiftEvidence.details.failedMutationCount, 0);
  assert.equal(swiftEvidence.details.connectionState, "authenticated");

  const ownerSnapshot = snapshot(await ownerDB.query(sharingQuery(ids.counterID)));
  const readerSnapshot = snapshot(await readerDB.query(sharingQuery(ids.counterID)));
  const writerSnapshot = snapshot(await writerDB.query(sharingQuery(ids.counterID)));
  const outsiderSnapshot = snapshot(await outsiderDB.query(sharingQuery(ids.counterID)));
  assert.deepStrictEqual(ownerSnapshot, {
    count: 1,
    title: "Canonical shared counter",
    value: 2,
    ownerID: users.owner.id,
    readerIDs: [],
    writerIDs: [users.writer.id],
    roles: ["owner", "writer"],
  });
  assert.equal(readerSnapshot.count, 0);
  assert.equal(writerSnapshot.count, 1);
  assert.equal(writerSnapshot.value, 2);
  assert.deepStrictEqual(writerSnapshot.roles, ["writer"]);
  assert.equal(outsiderSnapshot.count, 0);
  const revokedReaderUpdate = await rejected(
    readerDB.transact(
      readerDB.tx.v3_shared_lists[ids.counterID].update({ value: 99 }),
    ),
  );
  assert.match(revokedReaderUpdate, /permission/i);
  assert.deepStrictEqual(warnings, []);

  process.stdout.write(`${JSON.stringify({
    case: "validation.typescript.cloudkit-demo-v3-live-contract",
    event: "shared-counter-lifecycle-complete",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      ids,
      users: Object.fromEntries(
        Object.entries(users).map(([role, user]) => [role, {
          id: user.id,
          email: user.email,
        }]),
      ),
      beforeTypeScriptIncrement,
      final: {
        owner: ownerSnapshot,
        reader: readerSnapshot,
        writer: writerSnapshot,
        outsider: outsiderSnapshot,
      },
      revokedReaderUpdate,
      swift: swiftEvidence.details,
      compilerWarningCount: warnings.length,
      warnings,
    },
  }, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
}

function spawnSwift(input: {
  appId: string;
  apiURI: string;
  websocketURI: string;
  ids: typeof ids;
  users: Record<"owner" | "reader" | "writer" | "outsider", { id: string; token: string }>;
}): SwiftProcess {
  return spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-cloudkit-demo-v3",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: input.appId,
        INSTANT_API_URI: input.apiURI,
        INSTANT_WEBSOCKET_URI: input.websocketURI,
        INSTANT_SWIFT_DATA_CLOUDKIT_OWNER_REFRESH_TOKEN: input.users.owner.token,
        INSTANT_SWIFT_DATA_CLOUDKIT_OWNER_USER_ID: input.users.owner.id,
        INSTANT_SWIFT_DATA_CLOUDKIT_READER_REFRESH_TOKEN: input.users.reader.token,
        INSTANT_SWIFT_DATA_CLOUDKIT_READER_USER_ID: input.users.reader.id,
        INSTANT_SWIFT_DATA_CLOUDKIT_WRITER_USER_ID: input.users.writer.id,
        INSTANT_SWIFT_DATA_CLOUDKIT_COUNTER_ID: input.ids.counterID,
        INSTANT_SWIFT_DATA_CLOUDKIT_SHARE_ID: input.ids.shareID,
        INSTANT_SWIFT_DATA_CLOUDKIT_OWNER_MEMBERSHIP_ID: input.ids.ownerMembershipID,
        INSTANT_SWIFT_DATA_CLOUDKIT_READER_MEMBERSHIP_ID: input.ids.readerMembershipID,
        INSTANT_SWIFT_DATA_CLOUDKIT_WRITER_MEMBERSHIP_ID: input.ids.writerMembershipID,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
}

function snapshot(value: unknown) {
  const roots = requiredArray(requiredObject(value).v3_shared_lists, "v3_shared_lists");
  if (roots.length === 0) {
    return {
      count: 0,
      title: undefined,
      value: undefined,
      ownerID: undefined,
      readerIDs: [] as string[],
      writerIDs: [] as string[],
      roles: [] as string[],
    };
  }
  assert.equal(roots.length, 1);
  const root = requiredObject(roots[0], "v3_shared_lists[0]");
  const owner = requiredObject(root.owner, "v3_shared_lists[0].owner");
  const share = requiredObject(root.share, "v3_shared_lists[0].share");
  const memberships = requiredArray(share.memberships, "share.memberships");
  return {
    count: 1,
    title: requiredString(root.title, "title"),
    value: requiredNumber(root.value, "value"),
    ownerID: requiredString(owner.id, "owner.id"),
    readerIDs: entityIDs(root.readers),
    writerIDs: entityIDs(root.writers),
    roles: memberships.map((membership) =>
      requiredString(requiredObject(membership).role, "membership.role")
    ).sort(),
  };
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
  const code = await withTimeout(childExit(child), `${operation} exit`);
  if (code !== 0) throw new Error(`${operation} failed with status ${code}: ${stderr.trim()}`);
}

function childExit(child: SwiftProcess): Promise<number> {
  return new Promise((resolveExit) => child.once("exit", (code) => resolveExit(code ?? -1)));
}

async function rejected(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
  } catch (error) {
    return error instanceof Error ? `${error.name}: ${error.message}` : String(error);
  }
  throw new Error("Expected the transaction to be rejected.");
}

async function withTimeout<T>(promise: Promise<T>, operation: string): Promise<T> {
  let timeout: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<never>((_, reject) => {
        timeout = setTimeout(() => reject(new Error(`${operation} timed out.`)), 30_000);
      }),
    ]);
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}

function entityIDs(value: unknown): string[] {
  if (value === undefined) return [];
  return requiredArray(value, "linked entities")
    .map((entity) => requiredString(requiredObject(entity).id, "linked entity id"))
    .sort();
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}

function requiredObject(value: unknown, label = "value"): Record<string, any> {
  assert.ok(value && typeof value === "object" && !Array.isArray(value), `Expected ${label}.`);
  return value as Record<string, any>;
}

function requiredArray(value: unknown, label: string): unknown[] {
  assert.ok(Array.isArray(value), `Expected ${label} array.`);
  return value;
}

function requiredString(value: unknown, label: string): string {
  assert.equal(typeof value, "string", `Expected ${label} string.`);
  return value as string;
}

function requiredNumber(value: unknown, label: string): number {
  assert.equal(typeof value, "number", `Expected ${label} number.`);
  return value as number;
}
