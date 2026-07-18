import type { InstaQLParams, InstaQLResponse } from "@instantdb/core";

import type { AppSchema } from "../../fixtures/voice-trail.schema.js";

export type VoiceTrailRecordingsScope = "mine" | "shared";

export interface VoiceTrailRecordingsQueryInput {
  viewerID: string;
  scope: VoiceTrailRecordingsScope;
  searchText: string;
}

function recordingGraph(viewerID: string) {
  return {
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
  };
}

export function voiceTrailRecordingsQuery(
  input: VoiceTrailRecordingsQueryInput,
) {
  const searchText = input.searchText.trim();
  const title = searchText === ""
    ? {}
    : { title: { $ilike: `%${searchText}%` } };
  const graph = recordingGraph(input.viewerID);

  if (input.scope === "mine") {
    return {
      v3_capture_recordings: {
        $: {
          where: { "owner.id": input.viewerID, ...title },
          order: { title: "asc" },
        },
        ...graph,
      },
    } satisfies InstaQLParams<AppSchema>;
  }

  return {
    v3_capture_recordings: {
      $: {
        where: {
          or: [
            { "readers.id": input.viewerID },
            { "writers.id": input.viewerID },
          ],
          ...title,
        },
        order: { title: "asc" },
      },
      ...graph,
    },
  } satisfies InstaQLParams<AppSchema>;
}

export type VoiceTrailRecordingsQuery = ReturnType<
  typeof voiceTrailRecordingsQuery
>;
export type VoiceTrailRecordingsQueryResult = InstaQLResponse<
  AppSchema,
  VoiceTrailRecordingsQuery,
  true
>;
