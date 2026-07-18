import assert from "node:assert/strict";
import test from "node:test";

import {
  voiceTrailRecordingsQuery,
} from "./voice-trail-sdk-contract.js";
import { voiceTrailRuntimeSchema } from "./voice-trail-runtime-schema.js";

test("generated VoiceTrail schema loads as a runtime Admin SDK schema", () => {
  assert.deepStrictEqual(
    Object.keys(voiceTrailRuntimeSchema.entities).sort(),
    [
      "$users",
      "v3_capture_attachments",
      "v3_capture_recordings",
      "v3_capture_transcriptions",
      "v3_share_memberships",
      "v3_shares",
    ],
  );
});

test("VoiceTrail recordings list query preserves mine and shared graph shapes", () => {
  assert.deepStrictEqual(
    voiceTrailRecordingsQuery({
      viewerID: "user-viewer",
      scope: "mine",
      searchText: "walk",
    }),
    {
      v3_capture_recordings: {
        $: {
          where: {
            "owner.id": "user-viewer",
            title: { $ilike: "%walk%" },
          },
          order: { title: "asc" },
        },
        owner: {},
        readers: {},
        writers: {},
        share: {
          owner: {},
          memberships: {
            $: { where: { "user.id": "user-viewer" } },
            user: {},
          },
        },
      },
    },
  );

  assert.deepStrictEqual(
    voiceTrailRecordingsQuery({
      viewerID: "user-viewer",
      scope: "shared",
      searchText: "",
    }),
    {
      v3_capture_recordings: {
        $: {
          where: {
            or: [
              { "readers.id": "user-viewer" },
              { "writers.id": "user-viewer" },
            ],
          },
          order: { title: "asc" },
        },
        owner: {},
        readers: {},
        writers: {},
        share: {
          owner: {},
          memberships: {
            $: { where: { "user.id": "user-viewer" } },
            user: {},
          },
        },
      },
    },
  );
});
