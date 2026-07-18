import assert from "node:assert/strict";
import test from "node:test";

import {
  voiceTrailRecordingsQuery,
} from "./voice-trail-sdk-contract.js";

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
