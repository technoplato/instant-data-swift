import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { init } from "@instantdb/admin";

import {
  sharingGrantTransaction,
  sharingOwnerTransaction,
  sharingQuery,
} from "./sharing-sdk-contract.js";
import { sharingRuntimeSchema } from "./sharing-runtime-schema.js";

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const suffix = randomUUID();
const ids = {
  listID: randomUUID(),
  shareID: randomUUID(),
  ownerMembershipID: randomUUID(),
  readerMembershipID: randomUUID(),
  writerMembershipID: randomUUID(),
};
const emails = {
  owner: `sharing-owner-${suffix}@example.com`,
  reader: `sharing-reader-${suffix}@example.com`,
  writer: `sharing-writer-${suffix}@example.com`,
  outsider: `sharing-outsider-${suffix}@example.com`,
};
const warnings: string[] = [];
const originalWarn = console.warn;
console.warn = (...values) => warnings.push(values.map(String).join(" "));

try {
  const db = init({
    appId,
    adminToken,
    apiURI,
    schema: sharingRuntimeSchema,
    useDateObjects: true,
  });
  const identities = await Promise.all(
    Object.entries(emails).map(async ([role, email]) => {
      const token = await db.auth.createToken({ email });
      const user = await db.auth.verifyToken(token);
      assert.ok(user?.id, `Expected ${role} user id.`);
      return [role, { token, id: user.id, email }] as const;
    }),
  );
  const users = Object.fromEntries(identities) as Record<
    keyof typeof emails,
    { token: string; id: string; email: string }
  >;
  const ownerDB = db.asUser({ token: users.owner.token });
  const readerDB = db.asUser({ token: users.reader.token });
  const writerDB = db.asUser({ token: users.writer.token });
  const outsiderDB = db.asUser({ token: users.outsider.token });
  const createdAt = new Date("2026-07-18T20:00:00.000Z");

  await ownerDB.transact(
    sharingOwnerTransaction(ownerDB.tx, {
      ...ids,
      membershipID: ids.ownerMembershipID,
      ownerID: users.owner.id,
      token: `share-${suffix}`,
      title: "Canonical shared list",
      value: 1,
      now: createdAt,
    }),
  );

  await ownerDB.transact(
    sharingGrantTransaction(ownerDB.tx, {
      listID: ids.listID,
      shareID: ids.shareID,
      membershipID: ids.readerMembershipID,
      userID: users.reader.id,
      role: "reader",
      acceptedAt: new Date("2026-07-18T20:01:00.000Z"),
    }),
  );
  await ownerDB.transact(
    sharingGrantTransaction(ownerDB.tx, {
      listID: ids.listID,
      shareID: ids.shareID,
      membershipID: ids.writerMembershipID,
      userID: users.writer.id,
      role: "writer",
      acceptedAt: new Date("2026-07-18T20:02:00.000Z"),
    }),
  );

  const swiftReaderRejection = await runSwiftReaderRejection({
    appId,
    refreshToken: users.reader.token,
    readerUserID: users.reader.id,
    listID: ids.listID,
    expectedValue: 1,
    rejectedValue: 2,
  });
  assert.equal(swiftReaderRejection.ok, true);
  assert.deepStrictEqual(swiftReaderRejection.details.observedValues, [1, 2, 1]);
  assert.equal(swiftReaderRejection.details.pendingMutationCount, 0);
  assert.equal(swiftReaderRejection.details.failedMutationCount, 1);
  assert.match(swiftReaderRejection.details.failureMessage, /permission/i);

  const swiftWriterAcceptance = await runSwiftWriterAcceptance({
    appId,
    refreshToken: users.writer.token,
    writerUserID: users.writer.id,
    listID: ids.listID,
    expectedValue: 1,
    acceptedValue: 3,
  });
  assert.equal(swiftWriterAcceptance.ok, true);
  assert.deepStrictEqual(swiftWriterAcceptance.details.observedValues, [1, 3]);
  assert.equal(swiftWriterAcceptance.details.pendingMutationCount, 0);
  assert.equal(swiftWriterAcceptance.details.failedMutationCount, 0);

  const ownerResult = await ownerDB.query(sharingQuery(ids.listID));
  const readerResult = await readerDB.query(sharingQuery(ids.listID));
  const writerResult = await writerDB.query(sharingQuery(ids.listID));
  const outsiderResult = await outsiderDB.query(sharingQuery(ids.listID));

  const ownerSnapshot = sharingSnapshot(ownerResult);
  const readerSnapshot = sharingSnapshot(readerResult);
  const writerSnapshot = sharingSnapshot(writerResult);
  const outsiderSnapshot = sharingSnapshot(outsiderResult);
  assert.equal(ownerSnapshot.count, 1);
  assert.equal(readerSnapshot.count, 1);
  assert.equal(writerSnapshot.count, 1);
  assert.equal(outsiderSnapshot.count, 0);
  assert.equal(ownerSnapshot.ownerID, users.owner.id);
  assert.deepStrictEqual(ownerSnapshot.readerIDs, [users.reader.id]);
  assert.deepStrictEqual(ownerSnapshot.writerIDs, [users.writer.id]);
  assert.deepStrictEqual(
    ownerSnapshot.memberships.sort(),
    [
      ["owner", users.owner.id],
      ["reader", users.reader.id],
      ["writer", users.writer.id],
    ].sort(),
  );

  const readerUpdate = await rejected(
    readerDB.transact(
      readerDB.tx.v3_shared_lists[ids.listID].update({ value: 2 }),
    ),
  );
  await writerDB.transact(
    writerDB.tx.v3_shared_lists[ids.listID].update({ value: 3 }),
  );
  const readerDelete = await rejected(
    readerDB.transact(readerDB.tx.v3_shared_lists[ids.listID].delete()),
  );
  const writerDelete = await rejected(
    writerDB.transact(writerDB.tx.v3_shared_lists[ids.listID].delete()),
  );
  const finalSnapshot = sharingSnapshot(
    await ownerDB.query(sharingQuery(ids.listID)),
  );
  assert.equal(finalSnapshot.value, 3);

  process.stdout.write(`${JSON.stringify({
    case: "validation.typescript.sharing-live-contract",
    event: "summary",
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
      visibility: {
        owner: ownerSnapshot.count,
        reader: readerSnapshot.count,
        writer: writerSnapshot.count,
        outsider: outsiderSnapshot.count,
      },
      rejected: {
        readerUpdate,
        readerDelete,
        writerDelete,
      },
      finalValue: finalSnapshot.value,
      swiftReaderRejection: swiftReaderRejection.details,
      swiftWriterAcceptance: swiftWriterAcceptance.details,
      compilerWarningCount: warnings.length,
      warnings,
    },
  }, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
}

async function rejected(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
  } catch (error) {
    return error instanceof Error ? `${error.name}: ${error.message}` : String(error);
  }
  throw new Error("Expected user-scoped transaction to be rejected by permissions.");
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}

async function runSwiftReaderRejection(input: {
  appId: string;
  refreshToken: string;
  readerUserID: string;
  listID: string;
  expectedValue: number;
  rejectedValue: number;
}): Promise<{
  ok: boolean;
  details: {
    observedValues: number[];
    pendingMutationCount: number;
    failedMutationCount: number;
    failureMessage: string;
    connectionState: string;
  };
}> {
  const child = spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-sharing",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: input.appId,
        INSTANT_SWIFT_DATA_SHARING_REFRESH_TOKEN: input.refreshToken,
        INSTANT_SWIFT_DATA_SHARING_USER_ID: input.readerUserID,
        INSTANT_SWIFT_DATA_SHARING_LIST_ID: input.listID,
        INSTANT_SWIFT_DATA_SHARING_EXPECTED_VALUE: String(input.expectedValue),
        INSTANT_SWIFT_DATA_SHARING_REJECTED_VALUE: String(input.rejectedValue),
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
  const status = await new Promise<number>((resolveStatus, reject) => {
    child.once("error", reject);
    child.once("close", (code) => resolveStatus(code ?? 1));
  });
  if (status !== 0) {
    throw new Error(
      `Swift live sharing validation failed with status ${status}: ${stdout.trim()} ${stderr.trim()}`,
    );
  }
  const lines = stdout.trim().split("\n").filter(Boolean);
  if (lines.length !== 1) {
    throw new Error(`Expected one Swift sharing evidence row, received ${lines.length}.`);
  }
  return JSON.parse(lines[0]);
}

async function runSwiftWriterAcceptance(input: {
  appId: string;
  refreshToken: string;
  writerUserID: string;
  listID: string;
  expectedValue: number;
  acceptedValue: number;
}): Promise<{
  ok: boolean;
  details: {
    observedValues: number[];
    pendingMutationCount: number;
    failedMutationCount: number;
    connectionState: string;
  };
}> {
  const child = spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-sharing-writer",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: input.appId,
        INSTANT_SWIFT_DATA_SHARING_REFRESH_TOKEN: input.refreshToken,
        INSTANT_SWIFT_DATA_SHARING_USER_ID: input.writerUserID,
        INSTANT_SWIFT_DATA_SHARING_LIST_ID: input.listID,
        INSTANT_SWIFT_DATA_SHARING_EXPECTED_VALUE: String(input.expectedValue),
        INSTANT_SWIFT_DATA_SHARING_ACCEPTED_VALUE: String(input.acceptedValue),
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
  const status = await new Promise<number>((resolveStatus, reject) => {
    child.once("error", reject);
    child.once("close", (code) => resolveStatus(code ?? 1));
  });
  if (status !== 0) {
    throw new Error(
      `Swift live sharing writer validation failed with status ${status}: ${stdout.trim()} ${stderr.trim()}`,
    );
  }
  const lines = stdout.trim().split("\n").filter(Boolean);
  if (lines.length !== 1) {
    throw new Error(`Expected one Swift sharing writer evidence row, received ${lines.length}.`);
  }
  return JSON.parse(lines[0]);
}

function sharingSnapshot(value: unknown): {
  count: number;
  ownerID?: string;
  readerIDs: string[];
  writerIDs: string[];
  memberships: string[][];
  value?: number;
} {
  const roots = requiredArray(requiredObject(value).v3_shared_lists, "v3_shared_lists");
  if (roots.length === 0) {
    return { count: 0, readerIDs: [], writerIDs: [], memberships: [] };
  }
  assert.equal(roots.length, 1, "Expected exactly one shared list.");
  const root = requiredObject(roots[0], "v3_shared_lists[0]");
  const owner = requiredObject(root.owner, "v3_shared_lists[0].owner");
  const share = requiredObject(root.share, "v3_shared_lists[0].share");
  return {
    count: 1,
    ownerID: requiredString(owner.id, "owner.id"),
    readerIDs: requiredArray(root.readers, "readers")
      .map((reader) => requiredString(requiredObject(reader).id, "reader.id")),
    writerIDs: requiredArray(root.writers, "writers")
      .map((writer) => requiredString(requiredObject(writer).id, "writer.id")),
    memberships: requiredArray(share.memberships, "share.memberships")
      .map((membershipValue) => {
        const membership = requiredObject(membershipValue, "membership");
        const user = requiredObject(membership.user, "membership.user");
        return [
          requiredString(membership.role, "membership.role"),
          requiredString(user.id, "membership.user.id"),
        ];
      }),
    value: requiredNumber(root.value, "value"),
  };
}

function requiredObject(value: unknown, path = "value"): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`Expected ${path} to be an object.`);
  }
  return value as Record<string, unknown>;
}

function requiredArray(value: unknown, path: string): unknown[] {
  if (!Array.isArray(value)) throw new Error(`Expected ${path} to be an array.`);
  return value;
}

function requiredString(value: unknown, path: string): string {
  if (typeof value !== "string") throw new Error(`Expected ${path} to be a string.`);
  return value;
}

function requiredNumber(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`Expected ${path} to be a finite number.`);
  }
  return value;
}
