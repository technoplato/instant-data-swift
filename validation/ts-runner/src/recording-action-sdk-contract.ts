import type { InstaQLParams, InstaQLResponse } from "@instantdb/core";

import type { AppSchema } from "../../fixtures/recording-action.server.schema.js";

export function recordingActionQuery(recordingID: string) {
  return {
    v3_capture_recordings: {
      $: { where: { id: recordingID } },
      attachments: {},
      members: { user: {} },
      owner: {},
      transcriptions: {},
    },
  } satisfies InstaQLParams<AppSchema>;
}

export type RecordingActionQuery = ReturnType<typeof recordingActionQuery>;
export type RecordingActionQueryResult = InstaQLResponse<
  AppSchema,
  RecordingActionQuery,
  true
>;

export interface RecordingActionSnapshot {
  recording: {
    id: string;
    title: string;
    deviceID: string;
    state: string;
    durationMilliseconds: number;
    ownerID: string;
  };
  attachments: Array<{
    id: string;
    kind: string;
    contents: string;
    offsetMilliseconds: number;
  }>;
  members: Array<{
    id: string;
    role: string;
    userID: string;
  }>;
  transcriptions: Array<{
    id: string;
    state: string;
  }>;
}

export function recordingActionSnapshot(
  result: RecordingActionQueryResult,
): RecordingActionSnapshot {
  const [recording, ...unexpectedRecordings] = result.v3_capture_recordings;
  if (!recording || unexpectedRecordings.length > 0) {
    throw new Error(
      `Expected exactly one recording, received ${result.v3_capture_recordings.length}.`,
    );
  }
  if (!recording.owner) {
    throw new Error(`Recording ${recording.id} is missing its required owner link.`);
  }

  return {
    recording: {
      id: recording.id,
      title: requiredString(recording.title, "recording.title"),
      deviceID: requiredString(recording.deviceID, "recording.deviceID"),
      state: requiredString(recording.state, "recording.state"),
      durationMilliseconds: requiredNumber(
        recording.durationMilliseconds,
        "recording.durationMilliseconds",
      ),
      ownerID: recording.owner.id,
    },
    attachments: recording.attachments
      .map((attachment) => ({
        id: attachment.id,
        kind: requiredString(attachment.kind, "attachment.kind"),
        contents: requiredString(attachment.contents, "attachment.contents"),
        offsetMilliseconds: requiredNumber(
          attachment.offsetMilliseconds,
          "attachment.offsetMilliseconds",
        ),
      }))
      .sort(byID),
    members: recording.members
      .map((member) => {
        if (!member.user) {
          throw new Error(`Recording member ${member.id} is missing its required user link.`);
        }
        return {
          id: member.id,
          role: requiredString(member.role, "member.role"),
          userID: member.user.id,
        };
      })
      .sort(byID),
    transcriptions: recording.transcriptions
      .map((transcription) => ({
        id: transcription.id,
        state: requiredString(transcription.state, "transcription.state"),
      }))
      .sort(byID),
  };
}

function byID<A extends { id: string }>(lhs: A, rhs: A): number {
  return lhs.id.localeCompare(rhs.id);
}

function requiredString(value: unknown, path: string): string {
  if (typeof value !== "string") {
    throw new Error(`Expected ${path} to be a string, received ${typeof value}.`);
  }
  return value;
}

function requiredNumber(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`Expected ${path} to be a finite number.`);
  }
  return value;
}
