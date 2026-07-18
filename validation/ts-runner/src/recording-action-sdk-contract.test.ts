import assert from "node:assert/strict";
import test from "node:test";

import {
  recordingActionQuery,
  recordingActionSnapshot,
  type RecordingActionQueryResult,
} from "./recording-action-sdk-contract.js";

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
