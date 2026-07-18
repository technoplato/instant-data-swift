import assert from "node:assert/strict";
import test from "node:test";

import { recordingActionRuntimeSchema } from "./recording-action-runtime-schema.js";
import {
  recordingActionQuery,
  recordingActionResultIsReady,
  recordingActionSnapshot,
  type RecordingActionQueryResult,
  waitForRecordingActionResult,
} from "./recording-action-sdk-contract.js";

test("recording action server schema loads as a runtime SDK schema", () => {
  assert.ok(recordingActionRuntimeSchema.entities.v3_capture_recordings);
  assert.ok(recordingActionRuntimeSchema.entities.v3_capture_recordings.links.owner);
  assert.ok(recordingActionRuntimeSchema.entities.v3_capture_recordings.links.members);
  assert.ok(recordingActionRuntimeSchema.entities.v3_capture_recordings.links.attachments);
  assert.ok(recordingActionRuntimeSchema.entities.v3_capture_recordings.links.transcriptions);
});

test("recording action result readiness requires exactly one recording", () => {
  assert.equal(recordingActionResultIsReady(undefined), false);
  assert.equal(recordingActionResultIsReady({}), false);
  assert.equal(
    recordingActionResultIsReady({ v3_capture_recordings: [] }),
    false,
  );
  assert.equal(
    recordingActionResultIsReady({
      v3_capture_recordings: [{ id: "recording-e2e" }],
    }),
    false,
  );
  assert.equal(
    recordingActionResultIsReady(readyRecordingActionResult()),
    true,
  );
});

test("recording action result polling retries the canonical query", async () => {
  let calls = 0;
  const readyResult = readyRecordingActionResult();
  const result = await waitForRecordingActionResult(
    async () => {
      calls += 1;
      return calls < 3 ? undefined : readyResult;
    },
    { maxAttempts: 3, delayMilliseconds: 0 },
  );

  assert.equal(calls, 3);
  assert.equal(result.attemptCount, 3);
  assert.equal(result.value, readyResult);
});

test("recording action result polling retries transient query errors", async () => {
  let calls = 0;
  const readyResult = readyRecordingActionResult();
  const result = await waitForRecordingActionResult(
    async () => {
      calls += 1;
      if (calls === 1) throw new TypeError("transient empty SDK payload");
      return readyResult;
    },
    { maxAttempts: 2, delayMilliseconds: 0 },
  );

  assert.equal(calls, 2);
  assert.equal(result.attemptCount, 2);
  assert.equal(result.value, readyResult);
  assert.deepStrictEqual(result.queryErrors, [
    "TypeError: transient empty SDK payload",
  ]);
});

test("recording action query requests the entire canonical graph", () => {
  assert.deepStrictEqual(recordingActionQuery("recording-e2e"), {
    v3_capture_recordings: {
      $: { where: { id: "recording-e2e" } },
      attachments: {},
      members: { user: {} },
      owner: {},
      transcriptions: {},
    },
  });
});

test("recording action result projects the exact cross-SDK data shape", () => {
  const result = {
    v3_capture_recordings: [
      {
        id: "recording-e2e",
        title: "Canonical recording",
        deviceID: "swift-e2e",
        state: "recording",
        durationMilliseconds: 0,
        owner: {
          id: "owner-e2e",
          email: "owner-e2e@example.com",
        },
        attachments: [
          {
            id: "attachment-e2e",
            kind: "text",
            contents: "Cross-SDK notes",
            offsetMilliseconds: 2_500,
          },
        ],
        members: [
          {
            id: "member-e2e",
            role: "owner",
            user: {
              id: "owner-e2e",
              email: "owner-e2e@example.com",
            },
          },
        ],
        transcriptions: [
          {
            id: "transcription-e2e",
            state: "processing",
          },
        ],
      },
    ],
  } satisfies RecordingActionQueryResult;

  assert.deepStrictEqual(recordingActionSnapshot(result), {
    recording: {
      id: "recording-e2e",
      title: "Canonical recording",
      deviceID: "swift-e2e",
      state: "recording",
      durationMilliseconds: 0,
      ownerID: "owner-e2e",
    },
    attachments: [
      {
        id: "attachment-e2e",
        kind: "text",
        contents: "Cross-SDK notes",
        offsetMilliseconds: 2_500,
      },
    ],
    members: [
      {
        id: "member-e2e",
        role: "owner",
        userID: "owner-e2e",
      },
    ],
    transcriptions: [
      {
        id: "transcription-e2e",
        state: "processing",
      },
    ],
  });
});

function readyRecordingActionResult() {
  return {
    v3_capture_recordings: [
      {
        id: "recording-e2e",
        owner: { id: "owner-e2e" },
        attachments: [{ id: "attachment-e2e" }],
        members: [
          {
            id: "member-e2e",
            user: { id: "owner-e2e" },
          },
        ],
        transcriptions: [{ id: "transcription-e2e" }],
      },
    ],
  };
}
