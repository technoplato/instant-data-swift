import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { init } from "@instantdb/admin";

import { voiceTrailRuntimeSchema } from "./voice-trail-runtime-schema.js";

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI
  ?? "wss://api.instantdb.com/runtime/session";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const suffix = randomUUID();
const recordingID = randomUUID();
const transcriptionID = randomUUID();
const attachmentID = randomUUID();
const title = `VoiceTrail V3 app capture ${recordingID}`;
const deviceID = "swift-voicetrail-v3-app";
const attachmentKind = "screenshot";
const attachmentContents = "capture.png";
const attachmentOffsetMilliseconds = 2_500;
const durationMilliseconds = 12_750;
const warnings: string[] = [];
const originalWarn = console.warn;
console.warn = (...values) => warnings.push(values.map(String).join(" "));

try {
  const db = init({
    appId,
    adminToken,
    apiURI,
    schema: voiceTrailRuntimeSchema,
    useDateObjects: true,
  });
  const refreshToken = await db.auth.createToken({
    email: `voice-trail-v3-capture-${suffix}@example.com`,
  });
  const user = await db.auth.verifyToken(refreshToken);
  assert.ok(user?.id, "Expected a canonical VoiceTrail V3 capture user.");

  const swift = await runSwiftCapture({
    appId,
    apiURI,
    websocketURI,
    refreshToken,
    userID: user.id,
    recordingID,
    transcriptionID,
    attachmentID,
    title,
    deviceID,
    attachmentKind,
    attachmentContents,
    attachmentOffsetMilliseconds,
    durationMilliseconds,
  });
  assert.equal(swift.ok, true);
  assert.equal(swift.case, "validation.live.voice-trail-v3-capture");
  assert.deepEqual(swift.details, {
    direction: "swift-to-typescript",
    userID: user.id,
    recordingID,
    transcriptionID,
    attachmentID,
    title,
    deviceID,
    recordingState: "finished",
    durationMilliseconds,
    transcriptionState: "ready",
    attachmentKind,
    attachmentContents,
    attachmentOffsetMilliseconds,
    connectionState: "authenticated",
    pendingMutationCount: 0,
  });

  const observed = await waitForCapture(db, recordingID);
  assert.deepEqual(projectCapture(observed), {
    recordingID,
    transcriptionID,
    attachmentID,
    title,
    ownerUserID: user.id,
    deviceID,
    recordingState: "finished",
    durationMilliseconds,
    transcriptionState: "ready",
    attachmentKind,
    attachmentContents,
    attachmentOffsetMilliseconds,
  });
  assert.deepEqual(warnings, []);

  process.stdout.write(`${JSON.stringify({
    case: "validation.typescript.voice-trail-v3-capture-live-contract",
    event: "app-capture-observed",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      swift: swift.details,
      typescript: projectCapture(observed),
      compilerWarningCount: warnings.length,
      warnings,
    },
  }, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
}

async function runSwiftCapture(input: {
  appId: string;
  apiURI: string;
  websocketURI: string;
  refreshToken: string;
  userID: string;
  recordingID: string;
  transcriptionID: string;
  attachmentID: string;
  title: string;
  deviceID: string;
  attachmentKind: string;
  attachmentContents: string;
  attachmentOffsetMilliseconds: number;
  durationMilliseconds: number;
}): Promise<any> {
  const child = spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-voice-trail-v3-capture",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: input.appId,
        INSTANT_API_URI: input.apiURI,
        INSTANT_WEBSOCKET_URI: input.websocketURI,
        INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_REFRESH_TOKEN: input.refreshToken,
        INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_USER_ID: input.userID,
        INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_RECORDING_ID: input.recordingID,
        INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_TRANSCRIPTION_ID: input.transcriptionID,
        INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_ATTACHMENT_ID: input.attachmentID,
        INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_TITLE: input.title,
        INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_DEVICE_ID: input.deviceID,
        INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_ATTACHMENT_KIND: input.attachmentKind,
        INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_ATTACHMENT_CONTENTS: input.attachmentContents,
        INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_ATTACHMENT_OFFSET_MILLISECONDS:
          String(input.attachmentOffsetMilliseconds),
        INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_DURATION_MILLISECONDS:
          String(input.durationMilliseconds),
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
      `Swift VoiceTrail V3 capture validation failed with status ${exitCode}: ${stdout.trim()} ${stderr.trim()}`,
    );
  }
  const lines = stdout.trim().split("\n").filter(Boolean);
  if (lines.length !== 1) {
    throw new Error(`Expected one Swift capture evidence row, received ${lines.length}.`);
  }
  return JSON.parse(lines[0]);
}

async function waitForCapture(db: any, id: string): Promise<any> {
  let last: any;
  for (let attempt = 0; attempt < 80; attempt += 1) {
    last = await db.query({
      v3_capture_recordings: {
        $: { where: { id } },
        owner: {},
        transcriptions: {},
        attachments: {},
      },
    });
    const recording = last.v3_capture_recordings?.[0];
    if (
      recording?.state === "finished"
      && recording?.transcriptions?.[0]?.state === "ready"
      && recording?.attachments?.length === 1
    ) {
      return last;
    }
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 100));
  }
  throw new Error(`Timed out waiting for TypeScript capture query: ${JSON.stringify(last)}`);
}

function projectCapture(result: any) {
  const recording = result.v3_capture_recordings[0];
  const transcription = recording.transcriptions[0];
  const attachment = recording.attachments[0];
  return {
    recordingID: recording.id,
    transcriptionID: transcription.id,
    attachmentID: attachment.id,
    title: recording.title,
    ownerUserID: recording.owner.id,
    deviceID: recording.deviceID,
    recordingState: recording.state,
    durationMilliseconds: recording.durationMilliseconds,
    transcriptionState: transcription.state,
    attachmentKind: attachment.kind,
    attachmentContents: attachment.contents,
    attachmentOffsetMilliseconds: attachment.offsetMilliseconds,
  };
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}
