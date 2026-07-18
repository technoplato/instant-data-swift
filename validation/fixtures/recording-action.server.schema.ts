// Captured from the ephemeral Instant app after pushing the Swift-generated
// `recording-action` contract on July 18, 2026.
//
// This fixture intentionally includes Instant-managed entities, attributes,
// and links so Swift verification can distinguish known server normalization
// from application schema drift.

import { i } from "@instantdb/core";

const _schema = i.schema({
  entities: {
    $files: i.entity({
      path: i.string().unique().indexed(),
      url: i.string(),
    }),
    $streams: i.entity({
      abortReason: i.string().optional(),
      clientId: i.string().unique().indexed(),
      done: i.boolean().optional(),
      size: i.number().optional(),
    }),
    $users: i.entity({
      email: i.string().unique().indexed().optional(),
      imageURL: i.string().optional(),
      type: i.string().optional(),
    }),
    v3_capture_attachments: i.entity({
      contents: i.string(),
      kind: i.string().indexed(),
      offsetMilliseconds: i.number().indexed(),
    }),
    v3_capture_members: i.entity({
      role: i.string().indexed(),
    }),
    v3_capture_recordings: i.entity({
      deviceID: i.string().indexed(),
      durationMilliseconds: i.number().indexed(),
      state: i.string().indexed(),
      title: i.string().indexed(),
    }),
    v3_capture_transcriptions: i.entity({
      state: i.string().indexed(),
    }),
  },
  links: {
    $streams$files: {
      forward: {
        on: "$streams",
        has: "many",
        label: "$files",
      },
      reverse: {
        on: "$files",
        has: "one",
        label: "$stream",
        onDelete: "cascade",
      },
    },
    $usersLinkedPrimaryUser: {
      forward: {
        on: "$users",
        has: "one",
        label: "linkedPrimaryUser",
        onDelete: "cascade",
      },
      reverse: {
        on: "$users",
        has: "many",
        label: "linkedGuestUsers",
      },
    },
    v3_capture_attachmentsRecording: {
      forward: {
        on: "v3_capture_attachments",
        has: "one",
        label: "recording",
        required: true,
        onDelete: "cascade",
      },
      reverse: {
        on: "v3_capture_recordings",
        has: "many",
        label: "attachments",
      },
    },
    v3_capture_membersRecording: {
      forward: {
        on: "v3_capture_members",
        has: "one",
        label: "recording",
        required: true,
        onDelete: "cascade",
      },
      reverse: {
        on: "v3_capture_recordings",
        has: "many",
        label: "members",
      },
    },
    v3_capture_membersUser: {
      forward: {
        on: "v3_capture_members",
        has: "one",
        label: "user",
        required: true,
      },
      reverse: {
        on: "$users",
        has: "many",
        label: "recordingMemberships",
      },
    },
    v3_capture_recordingsOwner: {
      forward: {
        on: "v3_capture_recordings",
        has: "one",
        label: "owner",
        required: true,
      },
      reverse: {
        on: "$users",
        has: "many",
        label: "recordings",
      },
    },
    v3_capture_transcriptionsRecording: {
      forward: {
        on: "v3_capture_transcriptions",
        has: "one",
        label: "recording",
        required: true,
        onDelete: "cascade",
      },
      reverse: {
        on: "v3_capture_recordings",
        has: "many",
        label: "transcriptions",
      },
    },
  },
  rooms: {},
});

type _AppSchema = typeof _schema;
interface AppSchema extends _AppSchema {}
const schema: AppSchema = _schema;

export type { AppSchema };
export default schema;
