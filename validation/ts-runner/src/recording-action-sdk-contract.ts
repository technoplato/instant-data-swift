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

export function recordingActionResultIsReady(
  result: unknown,
): result is RecordingActionQueryResult {
  if (!result || typeof result !== "object") {
    return false;
  }
  const recordings = (result as Record<string, unknown>).v3_capture_recordings;
  if (!Array.isArray(recordings) || recordings.length !== 1) {
    return false;
  }
  const recording = objectValue(recordings[0]);
  if (!recording || !hasStringID(recording.owner)) {
    return false;
  }
  const attachments = recording.attachments;
  const members = recording.members;
  const transcriptions = recording.transcriptions;
  if (
    !Array.isArray(attachments)
    || attachments.length !== 1
    || !hasStringID(attachments[0])
    || !Array.isArray(members)
    || members.length !== 1
    || !hasStringID(members[0])
    || !hasStringID(objectValue(members[0])?.user)
    || !Array.isArray(transcriptions)
    || transcriptions.length !== 1
    || !hasStringID(transcriptions[0])
  ) {
    return false;
  }
  return true;
}

export async function waitForRecordingActionResult(
  query: () => Promise<unknown>,
  options: { maxAttempts?: number; delayMilliseconds?: number } = {},
): Promise<{
  value: RecordingActionQueryResult;
  attemptCount: number;
  queryErrors: string[];
}> {
  const maxAttempts = options.maxAttempts ?? 20;
  const delayMilliseconds = options.delayMilliseconds ?? 250;
  if (!Number.isInteger(maxAttempts) || maxAttempts <= 0) {
    throw new Error("maxAttempts must be a positive integer.");
  }
  if (!Number.isFinite(delayMilliseconds) || delayMilliseconds < 0) {
    throw new Error("delayMilliseconds must be a non-negative number.");
  }

  const queryErrors: string[] = [];
  let lastError: unknown;
  for (let attemptCount = 1; attemptCount <= maxAttempts; attemptCount += 1) {
    try {
      const value = await query();
      if (recordingActionResultIsReady(value)) {
        return { value, attemptCount, queryErrors };
      }
    } catch (error) {
      lastError = error;
      queryErrors.push(errorSummary(error));
    }
    if (attemptCount < maxAttempts && delayMilliseconds > 0) {
      await new Promise((resolve) => setTimeout(resolve, delayMilliseconds));
    }
  }

  const message = `Recording action query was not visible after ${maxAttempts} attempt(s).`;
  if (lastError !== undefined) {
    throw new Error(`${message} Last query error: ${errorSummary(lastError)}`, {
      cause: lastError,
    });
  }
  throw new Error(message);
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

function errorSummary(error: unknown): string {
  if (error instanceof Error) {
    return `${error.name}: ${error.message}`;
  }
  return String(error);
}

function objectValue(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object"
    ? value as Record<string, unknown>
    : undefined;
}

function hasStringID(value: unknown): boolean {
  return typeof objectValue(value)?.id === "string";
}
