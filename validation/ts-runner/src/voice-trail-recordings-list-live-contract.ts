import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createInterface } from "node:readline";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { init } from "@instantdb/admin";
import type { InstaQLParams, InstaQLResponse } from "@instantdb/core";

import schemaModule, {
  type AppSchema,
} from "../../fixtures/voice-trail.schema.js";

// The fixture is outside this package's ESM boundary, so tsx exposes its
// default value directly while NodeNext types the import as the module object.
const voiceTrailSchema = schemaModule as unknown as AppSchema;

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const suffix = randomUUID();
const ids = {
  recordingID: randomUUID(),
  shareID: randomUUID(),
  ownerMembershipID: randomUUID(),
  memberMembershipID: randomUUID(),
};
const warnings: string[] = [];
const originalWarn = console.warn;
console.warn = (...values) => warnings.push(values.map(String).join(" "));

try {
  const db = init({
    appId,
    adminToken,
    apiURI,
    schema: voiceTrailSchema,
    useDateObjects: true,
  });
  const users = Object.fromEntries(
    await Promise.all(
      (["owner", "member"] as const).map(async (role) => {
        const email = `voice-trail-${role}-${suffix}@example.com`;
        const token = await db.auth.createToken({ email });
        const user = await db.auth.verifyToken(token);
        assert.ok(user?.id, `Expected ${role} user id.`);
        return [role, { id: user.id, token, email }] as const;
      }),
    ),
  ) as Record<"owner" | "member", { id: string; token: string; email: string }>;
  const ownerDB = db.asUser({ token: users.owner.token });
  const memberDB = db.asUser({ token: users.member.token });
  const createdAt = new Date("2026-07-18T20:00:00.000Z");

  await ownerDB.transact([
    ownerDB.tx.v3_capture_recordings[ids.recordingID]
      .update({
        title: "Canonical shared recording",
        deviceID: "typescript-e2e",
        state: "ready",
        durationMilliseconds: 42_500,
      })
      .link({ owner: users.owner.id }),
    ownerDB.tx.v3_shares[ids.shareID]
      .update({
        token: `voice-trail-share-${suffix}`,
        rootNamespace: "v3_capture_recordings",
        rootID: ids.recordingID,
        createdAt,
        updatedAt: createdAt,
      })
      .link({ owner: users.owner.id, root: ids.recordingID }),
    ownerDB.tx.v3_share_memberships[ids.ownerMembershipID]
      .update({ role: "owner", acceptedAt: createdAt })
      .link({ share: ids.shareID, user: users.owner.id }),
    ownerDB.tx.v3_share_memberships[ids.memberMembershipID]
      .update({ role: "reader", acceptedAt: new Date("2026-07-18T20:01:00.000Z") })
      .link({ share: ids.shareID, user: users.member.id }),
    ownerDB.tx.v3_capture_recordings[ids.recordingID]
      .link({ readers: users.member.id }),
  ]);

  const ownerBefore = await ownerDB.query(
    recordingQuery(ids.recordingID, users.owner.id),
  );
  assertRecording(ownerBefore, {
    ownerID: users.owner.id,
    memberID: users.member.id,
    role: "reader",
  });
  const memberBefore = await memberDB.query(
    recordingQuery(ids.recordingID, users.member.id),
  );
  assertRecording(memberBefore, {
    ownerID: users.owner.id,
    memberID: users.member.id,
    role: "reader",
  });

  const ownerRows = await runSwift("owner", users.owner.token, users.owner.id);
  assert.deepStrictEqual(ownerRows.map((row) => row.details.stage), ["owner", "cancelled"]);
  assertSwiftStage(ownerRows[0], ids.recordingID, users.owner.id, "owner");
  assert.equal(ownerRows[1]?.details.cancellationClean, true);

  const memberRows = await runSwift(
    "member",
    users.member.token,
    users.member.id,
    async (stage) => {
      if (stage === "reader") {
        await ownerDB.transact([
          ownerDB.tx.v3_share_memberships[ids.memberMembershipID].update({ role: "writer" }),
          ownerDB.tx.v3_capture_recordings[ids.recordingID]
            .unlink({ readers: users.member.id })
            .link({ writers: users.member.id }),
        ]);
        const writer = await memberDB.query(
          recordingQuery(ids.recordingID, users.member.id),
        );
        assertRecording(writer, {
          ownerID: users.owner.id,
          memberID: users.member.id,
          role: "writer",
        });
      } else if (stage === "writer") {
        await ownerDB.transact([
          ownerDB.tx.v3_capture_recordings[ids.recordingID]
            .unlink({ writers: users.member.id }),
          ownerDB.tx.v3_share_memberships[ids.memberMembershipID].delete(),
        ]);
        const revoked = await memberDB.query(
          recordingQuery(ids.recordingID, users.member.id),
        );
        assert.deepStrictEqual(revoked.v3_capture_recordings, []);
      }
    },
  );
  assert.deepStrictEqual(
    memberRows.map((row) => row.details.stage),
    ["reader", "writer", "revoked", "cancelled"],
  );
  assertSwiftStage(memberRows[0], ids.recordingID, users.owner.id, "reader");
  assertSwiftStage(memberRows[1], ids.recordingID, users.owner.id, "writer");
  assert.deepStrictEqual(memberRows[2]?.details.rows, []);
  assert.equal(memberRows[3]?.details.cancellationClean, true);
  assert.deepStrictEqual(warnings, []);

  process.stdout.write(`${JSON.stringify({
    case: "validation.typescript.voice-trail-recordings-list-live",
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
      ownerStages: ownerRows.map((row) => row.details.stage),
      memberStages: memberRows.map((row) => row.details.stage),
      compilerWarningCount: warnings.length,
      warnings,
    },
  }, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
}

function recordingQuery(recordingID: string, viewerID: string) {
  return {
    v3_capture_recordings: {
      $: { where: { id: recordingID } },
      owner: {},
      readers: {},
      writers: {},
      share: {
        owner: {},
        memberships: {
          $: { where: { "user.id": viewerID } },
          user: {},
        },
      },
    },
  } satisfies InstaQLParams<AppSchema>;
}

type RecordingQuery = ReturnType<typeof recordingQuery>;
type RecordingResult = InstaQLResponse<AppSchema, RecordingQuery, true>;

function assertRecording(
  result: RecordingResult,
  expected: { ownerID: string; memberID: string; role: "reader" | "writer" },
): void {
  const recording = result.v3_capture_recordings[0];
  assert.ok(recording);
  assert.equal(recording.owner?.id, expected.ownerID);
  const members = recording.share?.memberships ?? [];
  assert.ok(
    members.some(
      (membership) => membership.user?.id === expected.memberID
        && membership.role === expected.role,
    ),
  );
}

interface SwiftEvidence {
  ok: boolean;
  details: {
    stage: string;
    viewerUserID: string;
    rows: Array<{
      id: string;
      title: string;
      ownerUserID: string;
      viewerRole?: string;
    }>;
    connectionState: string;
    cancellationClean?: boolean;
  };
}

async function runSwift(
  mode: "owner" | "member",
  refreshToken: string,
  viewerUserID: string,
  onStage: (stage: string) => Promise<void> = async () => {},
): Promise<SwiftEvidence[]> {
  const child = spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-voice-trail-recordings-list",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: appId,
        INSTANT_SWIFT_DATA_RECORDINGS_REFRESH_TOKEN: refreshToken,
        INSTANT_SWIFT_DATA_RECORDINGS_VIEWER_USER_ID: viewerUserID,
        INSTANT_SWIFT_DATA_RECORDINGS_RECORDING_ID: ids.recordingID,
        INSTANT_SWIFT_DATA_RECORDINGS_MODE: mode,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  let stderr = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const close = new Promise<number>((resolveStatus, reject) => {
    child.once("error", reject);
    child.once("close", (code) => resolveStatus(code ?? 1));
  });
  const rows: SwiftEvidence[] = [];
  const lines = createInterface({ input: child.stdout });
  for await (const line of lines) {
    if (!line.trim()) continue;
    const row = JSON.parse(line) as SwiftEvidence;
    rows.push(row);
    assert.equal(row.ok, true);
    await onStage(row.details.stage);
  }
  const status = await close;
  if (status !== 0) {
    throw new Error(`Swift VoiceTrail validation failed with status ${status}: ${stderr.trim()}`);
  }
  return rows;
}

function assertSwiftStage(
  row: SwiftEvidence | undefined,
  recordingID: string,
  ownerUserID: string,
  role: "owner" | "reader" | "writer",
): void {
  assert.ok(row);
  assert.deepStrictEqual(row.details.rows, [{
    id: recordingID,
    title: "Canonical shared recording",
    ownerUserID,
    viewerRole: role,
  }]);
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}
